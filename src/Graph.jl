# @license BSD-3 https://opensource.org/licenses/BSD-3-Clause
# Copyright (c) 2022, Institute of Automatic Control - RWTH Aachen University
# All rights reserved.

"""
    AbstractNode{name,child_names}
General graph traversing algorithms are defined on this type.
`name` is typically a symbol and `child_names` a tuple of symbols.

If a node is a leaf (has nod children), it does not depend on any other variables and should have a fully specified model.
"""
abstract type AbstractNode{name,child_names} end

"""
    nodename(node)
Extracts the name of the node
"""
nodename(::AbstractNode{name}) where {name} = name
"""
    childnames(node)
Extracts a tuple of the names of the child nodes.
"""
childnames(::AbstractNode{<:Any,names}) where {names} = names

# These fields are expected to be available in <:AbstractNode for the default implementations of rand_barrier and logdensityof_barrier

"""
    children(node)
Returns a tuple of the child nodes
"""
children(node::AbstractNode) = node.children
"""
    model(node)
Returns the callable model of the node.
Note that a Callable struct are not type stable and should be wrapped by a (anonymous) function.
"""
model(node::AbstractNode) = node.model
"""
    model(node)
Returns the random number generator of the node.
"""
rng(node::AbstractNode) = node.rng

# Interface: define custom behavior by dispatching on a specialized node type
# Also help with type stability

rand_barrier(node::AbstractNode{<:Any,()}, variables::NamedTuple, dims...) = rand(rng(node), node(variables), dims...)
# do not use dims.. in parent nodes which would lead to dimsᴺ where N=depth of the graph
rand_barrier(node::AbstractNode, variables::NamedTuple, dims...) = rand(rng(node), node(variables))

# Do only evaluate DeterministicNodes
evaluate_barrier(node::AbstractNode, variables::NamedTuple) = varvalue(node, variables)

logdensityof_barrier(node::AbstractNode, variables::NamedTuple) = logdensityof(node(variables), varvalue(node, variables))

bijector_barrier(node::AbstractNode, variables::NamedTuple) = bijector(node(variables))

"""
    traverse(fn, node, variables, [args...])
Effectively implements a depth first search to all nodes of the graph.

`fn(node, variables, args...)` is a function of the current `node`, the `variables` gathered from the recursions and `args` of the traverse function.
The return values of `fn` are accumulated in a NamedTuple indexed by the node name.
Only the first value of a node is considered, repeated calls for the same node name are ignored.
If `nothing` is returned, the value is ignored. p…
"""
function traverse(fn, node::AbstractNode{name}, variables::NamedTuple{varnames}, args...) where {name,varnames}
    #It is crucial that each node is executed only once for random sampling:
    # If a node is sampled multiple times for different paths, the variables are not consistent to each other.
    # Termination: Value already available (conditioned on or calculate via another path)
    if name in varnames
        return variables
    end
    # Conditional = values from other nodes required, compute depth first
    for child in children(node)
        variables = traverse(fn, child, variables, args...)
    end
    # Finally the internal dist can be realized and the value for this node can be merged
    value = fn(node, variables, args...)
    merge_value(variables, node, value)
end

"""
    merge_value(variables, node, value)
Right to left merges the value for the node with the correct name into the previously sampled variables.
Allows to override / modify previous values.
If the value is nothing, the variable does not get merged
"""
merge_value(variables, ::AbstractNode{name}, value) where {name} = (; variables..., name => value)
merge_value(variables, ::AbstractNode, ::Nothing) = variables

# Model interface

"""
    rand(node, [variables, dims...])
Generate the random variables from the model by traversing the child nodes.
Each node is evaluated only once and the dims are only applied to leafs.
The `variables` parameter allows to condition the model and will not be re-sampled.
"""
Base.rand(node::AbstractNode{varname}, variables::NamedTuple, dims::Integer...) where {varname} = traverse(rand_barrier, node, variables, dims...)
Base.rand(node::AbstractNode, dims::Integer...) = rand(node, (;), dims...)

"""
    evaluate(node, variables)
Evaluate only the deterministic nodes in the graph given the random `variables`.
All required random variables are assumed to be available.
"""
function evaluate(node::AbstractNode, variables::NamedTuple)
    # pass empty `variables` to traverse to evaluate all nodes
    nt = traverse(node, (;)) do current, _
        evaluate_barrier(current, variables)
    end
    merge(variables, nt)
end

"""
    logdensityof(node, variables)
Calculate the logdensity of the model given the variables by traversing the child nodes.
Each node is evaluated only once.
"""
DensityInterface.logdensityof(node::AbstractNode, variables::NamedTuple) = reduce(add_logdensity,
    traverse(node, (;)) do current, _
        logdensityof_barrier(current, variables)
    end)

"""
    bijector(node)
Infer the bijectors of the model by traversing the child nodes.
Internally a random is used to instantiate the models.
"""
function Bijectors.bijector(node::AbstractNode)
    variables = rand(node)
    traverse(node, (;), variables) do current, _...
        bijector_barrier(current, variables)
    end
end

"""
    prior(node)
The prior of a node are all the child nodes.
Returns a SequentializedGraph for the prior 
"""
prior(node::AbstractNode{name}) where {name} = Base.structdiff(sequentialize(node), (; name => ()))

"""
    parents(root::AbstractNode, node_name)
Returns a SequentializedGraph for the parents of the `node_name` node up until the `root` node.
"""
parents(root::AbstractNode, node_name) =
    traverse(root, (;)) do current, variables
        # current node is parent
        if node_name in childnames(current)
            return current
        end
        # one of the child nodes is parent
        if isempty(variables)
            return nothing
        end
        is_parent = mapreduce(|, keys(variables)) do var_name
            var_name in childnames(current)
        end
        if is_parent
            return current
        end
        return nothing
    end

parents(root::AbstractNode, nodes::AbstractNode...) =
    reduce(nodes; init=(;)) do accumulated, node
        nt = parents(root, nodename(node))
        # Merge only nodes which are not present in the evaluation model yet
        diff_nt = Base.structdiff(nt, accumulated)
        merge(accumulated, diff_nt)
    end

# Help to extract values from samples (NamedTuples)
childvalues(::AbstractNode{<:Any,child_names}, nt::NamedTuple) where {child_names} = values(nt[child_names])
varvalue(::AbstractNode{name}, nt::NamedTuple) where {name} = nt[name]
isleaf(node::AbstractNode) = node |> children |> isempty

# Helpers for the concrete realization of the internal model by extracting the matching variables
(node::AbstractNode)(x...) = model(node)(x...)
(node::AbstractNode)(nt::NamedTuple) = node(childvalues(node, nt)...)
# leaf does not depend on any other variables and should have a fully specified model
(node::AbstractNode{<:Any,()})(x...) = model(node)
(node::AbstractNode{<:Any,()})(::NamedTuple) = model(node)

# Base implementations
Base.Broadcast.broadcastable(x::AbstractNode) = Ref(x)
Base.show(io::IO, node::T) where {varname,child_names,T<:AbstractNode{varname,child_names}} = print(io, "$(Base.typename(T).wrapper){:$varname, $child_names}")
