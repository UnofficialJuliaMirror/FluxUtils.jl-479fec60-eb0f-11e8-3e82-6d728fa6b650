export FluxNet
abstract type FluxNet end

function xy2data(x, y, batchsize, seqsize)
    data = ((gpu.(eachcol(x[:, ib, is])), gpu.(eachcol(y[:, ib, is])))
            for is in indbatch(1:size(x, 3), seqsize)
            for ib in indbatch(1:size(x, 2), batchsize))
end

function fit!(net::FluxNet, x, y; epochs = 1, 
              batchsize = 50, seqsize = 300, 
              validation_data = nothing, validation_split = 0.0,  
              sample_weight = nothing, class_weight = nothing, 
              shuffle = false, cb = [])
    data = xy2data(x, y, batchsize, seqsize)
    Flux.@epochs epochs Flux.train!(partial(net.loss, net), data, net.opt; cb = [cugc, cb...])
end
