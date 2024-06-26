# @license BSD-3 https://opensource.org/licenses/BSD-3-Clause
# Copyright (c) 2022, Institute of Automatic Control - RWTH Aachen University
# All rights reserved. 

using Base: materialize
using BayesNet
using CUDA
using DensityInterface
using KernelDistributions
using Random
using Test

# Setup a list of rngs to loop over
cpurng = Random.default_rng()
Random.seed!(cpurng, 42)
if CUDA.functional()
    # Use CUDA only if available
    curng = CUDA.default_rng()
    Random.seed!(curng, 42)
    rngs = (cpurng, curng)
else
    rngs = (cpurng,)
end

CUDA.allowscalar(false)

include("math.jl")
include("simple.jl")
include("sequentialized.jl")
include("broadcasted.jl")
include("deterministic.jl")
include("modifier.jl")
include("observation.jl")
