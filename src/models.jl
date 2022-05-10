### MODELTYPE

function ModelType(name, subname=nothing;
    bases=[],
    props=[],
    abstract=false,
)
    propdescs = Dict{Symbol,PropDesc}()
    supers = IdSet{ModelType}()
    for t in bases
        abstract && !t.abstract && error("$name marked abstract but inherits from $(t.name) which is not abstract")
        mergepropdescs!(propdescs, t.propdescs)
        push!(supers, t)
        union!(supers, t.supers)
    end
    mergepropdescs!(propdescs, props)
    return ModelType(name, subname, bases, propdescs, supers, abstract)
end

function mergepropdescs!(ds, x; name=nothing)
    if x isa PropDesc
        ds[name] = x
    elseif x isa PropType
        ds[name] = PropDesc(x)
    elseif x isa Pair
        name = name===nothing ? x.first : Symbol(name, "_", x.first)
        mergepropdescs!(ds, x.second; name)
    elseif x isa Function
        d = ds[name]
        if d.kind == TYPE_K
            mergepropdescs!(ds, x(d.type); name)
        else
            mergepropdescs!(ds, x(d); name)
        end
    else
        for d in x
            mergepropdescs!(ds, d; name)
        end
    end
end

function (t::ModelType)(; kw...)
    @nospecialize
    Model(t, collect(Kwarg, kw))
end

issubmodeltype(t1::ModelType, t2::ModelType) = t1 === t2 || t2 in t1.supers

function Base.show(io::IO, t::ModelType)
    show(io, typeof(t))
    print(io, "(")
    show(io, t.name)
    print(io, "; ...)")
end

### MODEL

modelid(m::Model) = getfield(m, :id)

modeltype(m::Model) = getfield(m, :type)

modelvalues(m::Model) = getfield(m, :values)

ismodelinstance(m::Model, t::ModelType) = issubmodeltype(modeltype(m), t)

function Base.getproperty(m::Model, k::Symbol)
    # look up the value
    vs = modelvalues(m)
    v = get(vs, k, Undefined())
    v === Undefined() || return v
    # look up the descriptor
    mt = modeltype(m)
    ds = mt.propdescs
    pd = get(ds, k, nothing)
    pd === nothing && error("$(mt.name): .$k: invalid property")
    # branch on the kind of the descriptor
    kd = pd.kind
    if kd == TYPE_K
        # get the default value
        t = pd.type::PropType
        d = t.default
        if d === Undefined()
            v = d
        elseif d isa Function
            v = validate(t, d())
            v isa Invalid && error("$(mt.name): .$k: invalid default value: $(v.msg)")
            vs[k] = v
        else
            v = validate(t, d)
            v isa Invalid && error("$(mt.name): .$k: invalid default value: $(v.msg)")
        end
        return v
    elseif kd == GETSET_K
        f = pd.getter
        f === nothing && error("$(mt.name): .$k: property is not readable")
        return f(m)
    else
        @assert false
    end
end

function Base.setproperty!(m::Model, k::Symbol, x)
    # look up the descriptor
    mt = modeltype(m)
    ds = mt.propdescs
    pd = get(ds, k, nothing)
    pd === nothing && error("$(mt.name): .$k: invalid property")
    # branch on the kind of the descriptor
    kd = pd.kind
    if kd == TYPE_K
        if x === Undefined()
            # delete the value
            vs = modelvalues(m)
            delete!(vs, k)
        else
            # validate the value
            t = pd.type::PropType
            v = validate(t, x)
            v isa Invalid && error("$(mt.name): .$k: $(v.msg)")
            # set it
            vs = modelvalues(m)
            vs[k] = v
        end
    elseif kd == GETSET_K
        f = pd.setter
        f === nothing && error("$(mt.name): .$k: property is not writeable")
        f(m, x)
    else
        @assert false
    end
    return m
end

function Base.hasproperty(m::Model, k::Symbol)
    ts = modeltype(m).propdescs
    return haskey(ts, k)
end

function Base.propertynames(m::Model)
    ts = modeltype(m).propdescs
    return collect(keys(ts))
end

function Base.show(io::IO, m::Model)
    mt = modeltype(m)
    vs = modelvalues(m)
    print(io, mt.name, "(", join(["$k=$(repr(v))" for (k,v) in vs if v !== Undefined()], ", "), ")")
    return
end

Base.show(io::IO, ::MIME"text/plain", m::Model) = _show_indented(io, m)

function _show_indented(io::IO, m::Model, indent=0, seen=IdSet())
    if m in seen
        print(io, "...")
        return
    end
    push!(seen, m)
    mt = modeltype(m)
    vs = sort([x for x in modelvalues(m) if x[2] !== Undefined()], by=x->string(x[1]))
    print(io, mt.name, ":")
    istr = "  " ^ (indent + 1)
    if isempty(vs)
        print(io, " (blank)")
    else
        for (k, v) in vs
            println(io)
            print(io, istr, k, " = ")
            _show_indented(io, v, indent+1, seen)
        end
    end
    return
end

function _show_indented(io::IO, xs::AbstractVector, indent=0, seen=IdSet())
    if xs in seen
        print(io, "...")
        return
    end
    push!(seen, xs)
    if isempty(xs)
        print(io, "[]")
    else
        print(io, "[")
        istr = "  "^indent
        for (n, x) in enumerate(xs)
            println(io)
            print(io, istr, "  ")
            if n > 5
                print(io, "...")
                break
            else
                _show_indented(io, x, indent+1, seen)
            end
        end
        println(io)
        print(io, istr, "]")
    end
end

function _show_indented(io::IO, xs::AbstractDict, indent=0, seen=IdSet())
    if xs in seen
        print(io, "...")
        return
    end
    push!(seen, xs)
    if isempty(xs)
        print(io, "Dict()")
    else
        print(io, "Dict(")
        istr = "  "^indent
        for (n, (k, v)) in enumerate(xs)
            println(io)
            print(io, istr, "  ")
            if n > 5
                print(io, "...")
                break
            else
                show(io, k)
                print(io, " => ")
                _show_indented(io, v, indent+1, seen)
            end
        end
        println(io)
        print(io, istr, ")")
    end
end

function _show_indented(io::IO, x, indent=0, seen=IdSet())
    show(io, x)
end

function serialize(s::Serializer, m::Model)
    serialize_noref(s, m)
    id = modelid(m)
    return Dict("id" => id)
end

function serialize_noref(s::Serializer, m::Model)
    id = modelid(m)
    if get(s.refs, id, nothing) === m
        return s.refscache[id]
    end
    mt = modeltype(m)
    ds = mt.propdescs
    vs = modelvalues(m)
    attrs = Dict{String,Any}()
    for (k, v) in vs
        v === Undefined() && continue
        f = (ds[k].type::PropType).serialize
        k2 = string(k)
        v2 = f === nothing ? serialize(s, v) : f(s, v)
        attrs[k2] = v2
    end
    ans = Dict(
        "type"=>mt.name,
        "id"=>id,
        "attributes"=>attrs,
    )
    s.refs[id] = m
    s.refscache[id] = ans
    return ans
end

plot_get_renderers(plot::Model; type, sides, filter=nothing) = PropVector(Model[m::Model for side in sides for m in getproperty(plot, side) if ismodelinstance(m::Model, type) && (filter === nothing || filter(m::Model))])
plot_get_renderers(; kw...) = (plot::Model) -> plot_get_renderers(plot; kw...)

function plot_get_renderer(plot::Model; plural, kw...)
    ms = plot_get_renderers(plot; kw...)
    if length(ms) == 0
        return Undefined()
    elseif length(ms) == 1
        return ms[1]
    else
        error("multiple $plural defined, consider using .$plural instead")
    end
end
plot_get_renderer(; kw...) = (plot::Model) -> plot_get_renderer(plot; kw...)

generate_model_types()

const Figure = ModelType("Plot", "Figure", bases=[Plot])
export Figure
