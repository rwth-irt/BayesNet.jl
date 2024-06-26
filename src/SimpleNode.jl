# @license BSD-3 https://opensource.org/licenses/BSD-3-Clause
# Copyright (c) 2022, Institute of Automatic Control - RWTH Aachen University
# All rights reserved. 

"""
    SimpleNode(name, rng, distribution_type, children)
Basic implementation of an AbstractNode with the main purpose of unit testing the graph library.
Represents a named variable and depends on child nodes.
Does not support logdensityof multiple samples, since no broadcasting or reduction is implemented.
"""
struct SimpleNode{name,child_names,C<:Tuple{Vararg{AbstractNode}},R<:AbstractRNG,M} <: AbstractNode{name,child_names}
    children::C
    rng::R
    model::M
end

SimpleNode(name::Symbol, children::C, rng::R, model::M) where {C<:Tuple{Vararg{AbstractNode}},R<:AbstractRNG,M} = SimpleNode{name,nodename.(children),C,R,M}(children, rng, model)


# Parent node
function SimpleNode(name::Symbol, rng::AbstractRNG, ::Type{distribution}, children::Tuple) where {distribution}
    # Workaround so D is not UnionAll but interpreted as constructor
    wrapped(x...) = distribution(x...)
    SimpleNode(name, children, rng, wrapped)
end

# Leaf node
SimpleNode(name::Symbol, rng::AbstractRNG, distribution, params...) = SimpleNode(name, (), rng, distribution(params...))
