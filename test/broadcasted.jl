# @license BSD-3 https://opensource.org/licenses/BSD-3-Clause
# Copyright (c) 2022, Institute of Automatic Control - RWTH Aachen University
# All rights reserved. 

@testset "BroadcastedNode, RNG: $rng" for rng in rngs
    a_params = array_for_rng(rng, Float32, 3)
    a_params .= 1
    a = BroadcastedNode(:a, rng, KernelUniform, 0, a_params)

    # single rand
    nt = @inferred rand(a)
    @test nt.a isa AbstractArray{Float32,1}
    @test size(nt.a) == (3,)
    ℓ = @inferred logdensityof(a, nt)
    @test ℓ isa Float32
    @test ℓ == 0

    # multiple rand
    nt = @inferred rand(a, 2)
    @test nt.a isa AbstractArray{Float32,2}
    @test size(nt.a) == (3, 2)
    ℓ = @inferred logdensityof(a, nt)
    @test ℓ isa AbstractArray{Float32,1}
    @test size(ℓ) == (2,)
    res = array_for_rng(rng, Float32, 2)
    res .= 0
    @test ℓ == res

    # Graph
    b_params = array_for_rng(rng, Float32, 3, 4)
    b_params .= 1
    b = BroadcastedNode(:b, rng, KernelExponential, b_params)
    c = BroadcastedNode(:c, rng, KernelNormal, (a, b))

    # single rand
    nt = rand(c)
    @test nt.c isa AbstractArray{Float32,2}
    @test size(nt.c) == (3, 4)
    ℓ = logdensityof(c, nt)
    @test ℓ isa Float32

    # multiple rand
    nt = rand(c, 2)
    @test nt.c isa AbstractArray{Float32,3}
    @test size(nt.c) == (3, 4, 2)
    ℓ = logdensityof(c, nt)
    @test ℓ isa AbstractArray{Float32,1}
    @test size(ℓ) == (2,)

    # logdensityof for single sample
    d = BroadcastedNode(:d, rng, KernelNormal, (c, b))
    nt = rand(d)
    ℓ = logdensityof(d, nt)
    @test ℓ isa Float32
    @test ℓ ≈ sum(logdensityof.(KernelUniform(), nt.a) .+ logdensityof.(KernelExponential(), nt.b) .+ logdensityof.(KernelNormal.(nt.a, nt.b), nt.c) .+ logdensityof.(KernelNormal.(nt.c, nt.b), nt.d))

    # logdensityof for multiple samples
    nt = rand(d, 2)
    ℓ = logdensityof(d, nt)
    @test ℓ isa AbstractArray{Float32,1}
    a_val = reshape(nt.a, 3, 1, 2)
    b_val, c_val, d_val = nt.b, nt.c, nt.d
    broadcasted_sum = logdensityof.(KernelUniform(), a_val) .+ logdensityof.(KernelExponential(), b_val) .+ logdensityof.(KernelNormal.(a_val, b_val), c_val) .+ logdensityof.(KernelNormal.(c_val, b_val), d_val)
    @test ℓ ≈ dropdims(sum(broadcasted_sum; dims=(1, 2)); dims=(1, 2))

    # Bijectors
    bij = bijector(d)
    @test bij isa NamedTuple{(:a, :b, :c, :d)}
    a_bij = bijector(BroadcastedDistribution(KernelUniform, 0, a_params))
    @test bij.a.dims == a_bij.dims
    @test materialize(bij.a.bijectors) == materialize(a_bij.bijectors)
    b_bij = bijector(BroadcastedDistribution(KernelExponential, b_params))
    @test bij.b.dims == b_bij.dims
    @test materialize(bij.b.bijectors) == materialize(b_bij.bijectors)
    c_bij = bijector(BroadcastedDistribution(KernelNormal, 0, b_params))
    @test bij.c.dims == c_bij.dims
    @test materialize(bij.c.bijectors) == materialize(c_bij.bijectors)
    d_bij = bijector(BroadcastedDistribution(KernelNormal, 0, b_params))
    @test bij.d.dims == d_bij.dims
    @test materialize(bij.d.bijectors) == materialize(d_bij.bijectors)

    # Do the bijectors work for multiple samples?
    @test a_bij(nt.a) == bijector(KernelUniform(0, 1.0f0)).(nt.a)
    @test b_bij(nt.b) == bijector(KernelExponential(1.0f0)).(nt.b)
    @test c_bij(nt.c) == bijector(KernelNormal(0, 1.0f0)).(nt.c)
    @test d_bij(nt.d) == bijector(KernelNormal(0, 1.0f0)).(nt.d)
end