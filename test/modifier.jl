# @license BSD-3 https://opensource.org/licenses/BSD-3-Clause
# Copyright (c) 2022, Institute of Automatic Control - RWTH Aachen University
# All rights reserved. 

using BayesNet
using DensityInterface
using KernelDistributions
using Random
using Test

# Minimal implementation to test whether the values get modified and the rest of the graph is traversed
struct SimpleModifierModel end
# Construct with same args as wrapped model
SimpleModifierModel(args...) = SimpleModifierModel()
Base.rand(::AbstractRNG, model::SimpleModifierModel, value) = 10 * value
DensityInterface.logdensityof(::SimpleModifierModel, ::Any, ℓ) = ℓ + one(ℓ)

@testset "Simple ModifierNode, RNG: $rng" for rng in rngs
    a = SimpleNode(:a, rng, KernelUniform)
    b = SimpleNode(:b, rng, KernelExponential)
    c = SimpleNode(:c, rng, KernelNormal, (a, b))
    d = SimpleNode(:d, rng, KernelNormal, (c, b))
    d_mod = ModifierNode(d, rng, SimpleModifierModel)

    nt = rand(d_mod)
    @test logdensityof(d, nt) == logdensityof(d_mod, nt) - 1
    bij = bijector(d_mod)
    @test bij isa NamedTuple{(:a, :b, :c, :d)}
    @test values(bij) == (bijector(KernelUniform()), bijector(KernelExponential()), bijector(KernelNormal()), bijector(KernelNormal()))
end
