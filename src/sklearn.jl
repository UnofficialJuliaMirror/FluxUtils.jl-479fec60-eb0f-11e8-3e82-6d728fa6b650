using Base: Generator, product

export part, mpipart, rebatch, datagen, Estimator, TrainSpec, seqloss

function part(x, n = myid() - 1, N = nworkers(); dim = ndims(x))
    (n < 1 || size(x)[dim] < N) && return x
    is = chunk(1:size(x, dim), N)
    i = UnitRange(extrema(is[n])...)
    inds = ntuple(x -> x == dim ? i : (:), ndims(x))
    view(x, inds...)
end

mpipart(x) = part(x, myid(), nprocs())

function rebatch(x::AbstractMatrix, batchsize)
    nb, nt = size(x, 1), size(x, 2)
    n = batchsize ÷ nb
    (n <= 1 || nt <= n) && return x
    nt′, nb′ = nt ÷ n, nb * n
    xt = view(x, :, 1:(nt′ * n))
    xp = PermutedDimsArray(xt, [2, 1])
    xr = reshape(xp, nt′, nb′)
    PermutedDimsArray(xr, [2, 1])
end

function rebatch(x::AbstractArray{T, 3}, batchsize) where T
    nb, nt = size(x, 2), size(x, 3)
    n = batchsize ÷ nb
    (n <= 1 || nt <= n) && return x
    nt′, nb′ = nt ÷ n, nb * n
    xt = view(x, :, :, 1:(nt′ * n))
    xp = PermutedDimsArray(xt, [1, 3, 2])
    xr = reshape(xp, :, nt′, nb′)
    PermutedDimsArray(xr, [1, 3, 2])
end

function datagen(x, batchsize, seqsize; partf = part, trans = identity)
    x = rebatch(partf(x), batchsize)
    titr = indbatch(1:size(x, 3), seqsize)
    bitr = indbatch(1:size(x, 2), batchsize)
    Generator(product(titr, bitr)) do args
        ts, bs = args
        [trans(view(x, :, bs, t)) for t in ts]
    end
end

function datagen(x, batchsize; partf = part, trans = identity)
    x = rebatch(partf(x), batchsize)
    titr = 1:size(x, 3)
    bitr = indbatch(1:size(x, 2), batchsize)
    Generator(product(titr, bitr)) do args
        t, bs = args
        trans(view(x, :, bs, t))
    end
end

datagen(x::Tuple, args...; kwargs...) = zip(datagen.(x, args...; kwargs...)...)

Base.fill!(As::Tuple, x) = fill!.(As, x)

Base.copyto!(dests::Tuple, srcs::Tuple) = copyto!.(dests, srcs)

checkdims(xs...) = prefor(x -> x isa AbstractArray && ndims(x) != 3 && error("ndims should be 3"), xs)

mutable struct Estimator{M, L, O, C}
    model::M
    loss::L
    opt::O
    spec::C
end

function Base.show(io::IO, est::Estimator)
    io = IOContext(io, :compact => true)
    println(io, "model:")
    for s in fieldnames(typeof(est.model))
        x = getfield(est.model, s)
        x = x == nothing ? "nithing" : x
        println(io, ' '^2, s, ": ", x)
    end
    println(io, "loss: ", repr("text/plain", est.loss))
    println(io, "opt: ", repr("text/plain", est.opt))
    println(io, "spec: ", est.spec)
end

@treelike Estimator

@with_kw mutable struct TrainSpec
    epochs::Int = 1
    batchsize::Int = 100
    seqsize::Int = 1000
end

function fit!(est::Estimator, x, y, w = nothing; kws...)
    @unpack model, loss, opt, spec = est
    @unpack epochs, batchsize, seqsize = spec
    haskey(kws, :epochs) && @unpack epochs = kws
    runopt = haskey(kws, :runopt) ? kws[:runopt] : true
    runopt && @isdefined(MPI) && syncparam!(est)
    dx = datagen(x, batchsize, seqsize, partf = mpipart, trans = gpu)
    dy = datagen(y, batchsize, seqsize, partf = mpipart, trans = gpu)
    if w == nothing
        data = zip(dx, dy)
    else
        rmul!(w, 1 / mean(w))
        dw = datagen(w, batchsize, seqsize, partf = mpipart)
        data = zip(dx, dy, dw)
    end
    local l, ∇l
    for n in 1:epochs
        desc = nprocs() == 1 ? @sprintf("epoch-%d ", n) :
                @sprintf("worker-%d,epoch-%d ", myid(), n)
        l, ∇l = train!(model, loss, data, opt; desc = desc, kws...)
    end
    return l, ∇l
end

function predict!(ŷ, est::Estimator, x)
    @unpack model, spec = est
    @unpack batchsize, seqsize = spec
    model = notrack(model)
    fill!(ŷ, 0f0) # in case of partial copy
    dx = datagen(x, batchsize, partf = identity, trans = gpu ∘ copy)
    dy = datagen(ŷ, batchsize, partf = identity)
    for (xi, yi) in zip(dx, dy)
        copyto!(yi, notrack(cpu(model(xi))))
    end
    return ŷ
end

function seqloss(loss)
    function (m, xs, ys)
        l, T = 0f0, length(xs)
        for t in 1:T
            x, y = xs[t], ys[t]
            l += loss(m(x), y)
        end
        return l / Float32(T)
    end
end
