using Flux.Optimise: optimiser, invdecay, descent, descentweightdecay, momentum, rmsprop, adam, clip, Param
using Flux.Optimise: back!, runall, @progress, @interrupts

@init @suppress begin

Flux.Optimise.ADAMW(ps, η = 1f-3; β1 = 0.9f0, β2 = 0.999f0, ϵ = 1f-8, decay = 0f0, thresh = 0.5f0) =
  optimiser(ps, p -> clip(p, thresh), p -> adam(p; η = η, β1 = β1, β2 = β2, ϵ = ϵ), 
                p -> descentweightdecay(p, 1, decay))
       
Flux.Optimise.SGD(ps, η = 1f-1; decay = 0f0, thresh = 0.5f0) =
  optimiser(ps, p -> clip(p, thresh), p -> invdecay(p, decay), p -> descent(p, η))

Flux.Optimise.Momentum(ps, η = 1f-2; ρ = 0.9f0, decay = 0f0, thresh = 0.5f0) =
  optimiser(ps, p -> clip(p, thresh), p -> invdecay(p,decay), 
                p -> momentum(p, ρ, η), p -> descent(p, 1))

Flux.Optimise.RMSProp(ps, η = 1f-3; ρ = 0.9f0, ϵ = 1f-8, decay = 0f0, thresh = 0.5f0) =
  optimiser(ps, p -> clip(p, thresh), p -> rmsprop(p; η = η, ρ = ρ, ϵ = ϵ), 
                p -> invdecay(p, decay), p -> descent(p, 1))

Flux.Optimise.ADAM(ps, η = 1f-3; β1 = 0.9f0, β2 = 0.999f0, ϵ = 1f-8, decay = 0f0, thresh = 0.5f0) =
  optimiser(ps, p -> clip(p, thresh), p -> adam(p; η = η, β1 = β1, β2 = β2, ϵ = ϵ), 
                p -> invdecay(p, decay), p -> descent(p, 1))

function Flux.Optimise.train!(m, loss, data, opt; logintvl = 10, cb = [])
    cb = runall(cb)
    opt = runall(opt)
    ltot, nbatch = 0f0, 0
    logcb = throttle(plog, logintvl)
    for (i, d) in enumerate(data)
        l = loss(m, d...)
        if i % size(data, 1) == 0
            Flux.reset!(m)
        else
            Flux.truncate!(m)
        end
        ltot += Flux.data(l)
        nbatch += 1
        logcb("Loss", l)
        isinf(l) && error("Loss is Inf")
        isnan(l) && error("Loss is NaN")
        @interrupts back!(l)
        opt()
        cb() == :stop && break
    end
    plog("AvgLoss", ltot / nbatch, :yellow)
end

end