### MODELTYPE

function ModelType(name, subname=nothing;
    inherits=[BaseModel],
    props=[],
)
    propdescs = Dict{Symbol,PropDesc}()
    supers = IdSet{ModelType}()
    for t in inherits
        mergepropdescs!(propdescs, t.propdescs)
        push!(supers, t)
        union!(supers, t.supers)
    end
    mergepropdescs!(propdescs, props)
    return ModelType(name, subname, inherits, propdescs, supers)
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


### BASE

const BaseModel = ModelType("Model",
    inherits = [],
    props = [
        :name => NullableT(StringT()),
        :tags => ListT(AnyT()),
        :syncable => BoolT() |> DefaultT(true),
    ],
)


### TEXT

const BaseText = ModelType("BaseText";
    props = [
        :text => StringT(),
    ]
)

const MathText = ModelType("MathText";
    inherits = [BaseText],
)

const Ascii = ModelType("Ascii";
    inherits = [MathText],
)

const MathML = ModelType("MathML";
    inherits = [MathText],
)

const TeX = ModelType("TeX";
    inherits = [MathText],
    props = [
        :macros => DictT(StringT(), EitherT(StringT(), TupleT(StringT(), IntT()))),
        :inline => BoolT(default=false),
    ]
)

const PlainText = ModelType("PlainText";
    inherits = [BaseText],
)

module Math
    import ..Bokeh: MathText, Ascii, MathML, TeX
    export MathText, Ascii, MathML, TeX
end


### SOURCES

const DataSource = ModelType("DataSource")

const ColumnarDataSource = ModelType("ColumnarDataSource";
    inherits = [DataSource],
)

const ColumnDataSource = ModelType("ColumnDataSource";
    inherits = [ColumnarDataSource],
    props = [
        :data => ColumnDataT(),
        :column_names => GetSetT(x->collect(String,keys(x.data))),
    ],
)

const CDSView = ModelType("CDSView";
    props = [
        :filters => ListT(AnyT()),
        :source => InstanceT(ColumnarDataSource),
    ],
)

module Sources
    import ..Bokeh: DataSource, ColumnarDataSource, ColumnDataSource, CDSView
    export DataSource, ColumnarDataSource, ColumnDataSource, CDSView
end

### TICKERS

const Ticker = ModelType("Ticker")

const ContinuousTicker = ModelType("ContinuousTicker";
    inherits = [Ticker],
    props = [
        :num_minor_ticks => IntT(default=5),
        :desired_num_ticks => IntT(default=6),
    ]
)

const FixedTicker = ModelType("FixedTicker";
    inherits = [ContinuousTicker],
    props = [
        :ticks => SeqT(FloatT()),
        :minor_ticks => SeqT(FloatT()),
    ]
)

const AdaptiveTicker = ModelType("AdaptiveTicker";
    inherits = [ContinuousTicker],
    props = [
        :base => FloatT(default=10.0),
        :mantissas => SeqT(FloatT(), default=()->[1.0, 2.0, 5.0]),
        :min_interval => FloatT(default=0.0),
        :max_interval => NullableT(FloatT()),
    ]
)

const CompositeTicker = ModelType("CompositeTicker";
    inherits = [ContinuousTicker],
    props = [
        :tickers => SeqT(InstanceT(Ticker)),
    ]
)

const SingleIntervalTicker = ModelType("SingleIntervalTicker";
    inherits = [ContinuousTicker],
    props = [
        :interval => FloatT(),
    ]
)

const DaysTicker = ModelType("DaysTicker";
    inherits = [SingleIntervalTicker],
    props = [
        :days => SeqT(IntT()),
        :num_minor_ticks => DefaultT(0),
    ]
)

const MonthsTicker = ModelType("MonthsTicker";
    inherits = [SingleIntervalTicker],
    props = [
        :months => SeqT(IntT()),
    ]
)

const YearsTicker = ModelType("YearsTicker";
    inherits = [SingleIntervalTicker],
)

const BasicTicker = ModelType("BasicTicker";
    inherits = [AdaptiveTicker],
)

const LogTicker = ModelType("LogTicker";
    inherits = [AdaptiveTicker],
    props = [
        :mantissas => DefaultT(()->[1.0, 5.0]),
    ]
)

const MercatorTicker = ModelType("MercatorTicker";
    inherits = [BasicTicker],
    props = [
        :dimension => NullableT(LatLonT()),
    ]
)

const DatetimeTicker = ModelType("DatetimeTicker";
    inherits = [CompositeTicker],
    props = [
        :num_minor_ticks => DefaultT(0),
        :tickers => DefaultT(() -> [
            AdaptiveTicker(
                mantissas = [1, 2, 5],
                base = 10,
                min_interval = 0,
                max_interval = 500,
                num_minor_ticks = 0,
            ),
            AdaptiveTicker(
                mantissas = [1, 2, 5, 10, 15, 20, 30],
                base = 60,
                min_interval = 1000,
                max_interval = 30*60*1000,
                num_minor_ticks = 0,
            ),
            AdaptiveTicker(
                mantissas = [1, 2, 4, 6, 8, 12],
                base = 60,
                min_interval = 60*60*1000,
                max_interval = 12*60*60*1000,
                num_minor_ticks = 0,
            ),
            DaysTicker(days=collect(1:32)),
            DaysTicker(days=collect(1:3:30)),
            DaysTicker(days=[1,8,15,22]),
            DaysTicker(days=[1,15]),
            MonthsTicker(months=collect(0:1:11)),
            MonthsTicker(months=collect(0:2:11)),
            MonthsTicker(months=collect(0:3:11)),
            MonthsTicker(months=collect(0:6:11)),
            YearsTicker(),
        ])
    ]
)

const BinnedTicker = ModelType("BinnedTicker";
    inherits = [Ticker],
    props = [
        # :mapper => InstanceT(ScanningColorMapper), TODO
        :num_major_ticks => EitherT(IntT(), AutoT(), default=8),
    ]
)

module Tickers
    import ..Bokeh: Ticker, ContinuousTicker, FixedTicker, AdaptiveTicker, CompositeTicker,
        SingleIntervalTicker, DaysTicker, MonthsTicker, YearsTicker, BasicTicker,
        LogTicker, MercatorTicker, DatetimeTicker, BinnedTicker
    export Ticker, ContinuousTicker, FixedTicker, AdaptiveTicker, CompositeTicker,
        SingleIntervalTicker, DaysTicker, MonthsTicker, YearsTicker, BasicTicker,
        LogTicker, MercatorTicker, DatetimeTicker, BinnedTicker
end


### TICK FORMATTERS

const TickFormatter = ModelType("TickFormatter")

const BasicTickFormatter = ModelType("BasicTickFormatter";
    inherits = [TickFormatter],
    props = [
        :precision => EitherT(AutoT(), IntT()),
        :use_scientific => BoolT(default=true),
        :power_limit_high => IntT(default=5),
        :power_limit_low => IntT(default=-3),
    ]
)

const MercatorTickFormatter = ModelType("MercatorTickFormatter";
    inherits = [BasicTickFormatter],
    props = [
        :dimension => NullableT(LatLonT()),
    ]
)

const NumericalTickFormatter = ModelType("NumericalTickFormatter";
    inherits = [TickFormatter],
    props = [
        :format => StringT(default="0,0"),
        :language => NumeralLanguageT(default="en"),
        :rounding => RoundingFunctionT(),
    ]
)

const PrintfTickFormatter = ModelType("PrintfTickFormatter";
    inherits = [TickFormatter],
    props = [
        :format => StringT(default="%s"),
    ]
)

const LogTickFormatter = ModelType("LogTickFormatter";
    inherits = [TickFormatter],
    props = [
        :ticker => NullableT(InstanceT(Ticker)),
        :min_exponent => IntT(default=0),
    ]
)

const CategoricalTickFormatter = ModelType("CategoricalTickFormatter";
    inherits = [TickFormatter],
)

const FuncTickFormatter = ModelType("FuncTickFormatter";
    inherits = [TickFormatter],
    props = [
        # TODO
    ]
)

const DatetimeTickFormatter = ModelType("DatetimeTickFormatter";
    inherits = [TickFormatter],
    props = [
        :microseconds => ListOrSingleT(StringT(), default=()->["%fus"]),
        :milliseconds => ListOrSingleT(StringT(), default=()->["%3Nms", "%S.%3Ns"]),
        :seconds => ListOrSingleT(StringT(), default=()->["%Ss"]),
        :minsec => ListOrSingleT(StringT(), default=()->[":%M:%S"]),
        :minutes => ListOrSingleT(StringT(), default=()->[":%M", "%Mm"]),
        :hourmin => ListOrSingleT(StringT(), default=()->["%H:%M"]),
        :hours => ListOrSingleT(StringT(), default=()->["%Hh", "%H:%M"]),
        :days => ListOrSingleT(StringT(), default=()->["%m/%d", "%a%d"]),
        :months => ListOrSingleT(StringT(), default=()->["%m/%Y", "%b %Y"]),
        :years => ListOrSingleT(StringT(), default=()->["%Y"]),
    ]
)

module TickFormatters
    import ..Bokeh: TickFormatter, BasicTickFormatter, MercatorTickFormatter,
        NumericalTickFormatter, PrintfTickFormatter, LogTickFormatter,
        CategoricalTickFormatter, FuncTickFormatter, DatetimeTickFormatter
    export TickFormatter, BasicTickFormatter, MercatorTickFormatter,
        NumericalTickFormatter, PrintfTickFormatter, LogTickFormatter,
        CategoricalTickFormatter, FuncTickFormatter, DatetimeTickFormatter
end



### LAYOUTS

const LayoutDOM = ModelType("LayoutDOM";
    props = [
        :disabled => BoolT(default=false),
        :visible => BoolT(default=true),
        :width => NullableT(NonNegativeIntT()),
        :height => NullableT(NonNegativeIntT()),
        :min_width => NullableT(NonNegativeIntT()),
        :min_height => NullableT(NonNegativeIntT()),
        :max_width => NullableT(NonNegativeIntT()),
        :max_height => NullableT(NonNegativeIntT()),
        :margin => NullableT(MarginT(), default=(0,0,0,0)),
        :width_policy => EitherT(AutoT(), SizingPolicyT(), default="auto"),
        :height_policy => EitherT(AutoT(), SizingPolicyT(), default="auto"),
        :aspect_ratio => EitherT(AutoT(), NullT(), FloatT()),
        :sizing_mode => NullableT(SizingModeT()),
        :align => EitherT(AlignT(), TupleT(AlignT(), AlignT()), default="start"),
        :background => NullableT(ColorT()),
        :css_classes => ListT(StringT()),
    ]
)

const HTMLBox = ModelType("HTMLBox";
    inherits = [LayoutDOM],
)

const Spacer = ModelType("Spacer";
    inherits = [LayoutDOM]
)

const GridBox = ModelType("GridBox";
    inherits = [LayoutDOM],
)

const Box = ModelType("Box";
    inherits = [LayoutDOM],
    props = [
        :children => ListT(InstanceT(LayoutDOM)),
        :spacing => IntT(default=0),
    ]
)

const Row = ModelType("Row";
    inherits = [Box],
    props = [
        :cols => EitherT(QuickTrackSizingT(), DictT(IntOrStringT(), ColSizingT()), default="auto"),
    ]
)

const Column = ModelType("Column";
    inherits = [Box],
    props = [
        :cols => EitherT(QuickTrackSizingT(), DictT(IntOrStringT(), RowSizingT()), default="auto"),
    ]
)

module Layouts
    import ..Bokeh: LayoutDOM, HTMLBox, Spacer, GridBox, Box, Row, Column
    export LayoutDOM, HTMLBox, Spacer, GridBox, Box, Row, Column
end


### TRANSFORMS

const Transform = ModelType("Transform")


### MAPPERS

const Mapper = ModelType("Mapper";
    inherits = [Transform],
)

const ColorMapper = ModelType("ColorMapper";
    inherits = [Mapper],
    props = [
        :palette => PaletteT(),
        :nan_color => ColorT() |> DefaultT("gray"),
    ],
)

const CategoricalMapper = ModelType("CategoricalMapper";
    inherits = [Mapper],
    props = [
        :factors => FactorSeqT(),
        :start => IntT() |> DefaultT(0),
        :end => IntT() |> NullableT,
    ],
)

const CategoricalColorMapper = ModelType("CategoricalColorMapper";
    inherits = [ColorMapper, CategoricalMapper],
)

const CategoricalMarkerMapper = ModelType("CategoricalMarkerMapper";
    inherits = [CategoricalMapper],
    props = [
        :markers => ListT(MarkerT()),
        :default_value => MarkerT() |> DefaultT("circle"),
    ]
)

const CategoricalPatternMapper = ModelType("CategoricalPatternMapper";
    inherits = [CategoricalMapper],
)

const ContinuousColorMapper = ModelType("ContinuousColorMapper";
    inherits = [ColorMapper],
)

const LinearColorMapper = ModelType("LinearColorMapper";
    inherits = [ContinuousColorMapper],
)

const LogColorMapper = ModelType("LogColorMapper";
    inherits = [ContinuousColorMapper],
)

module Mappers
    import ..Bokeh: Mapper, ColorMapper, CategoricalMapper, CategoricalColorMapper,
        CategoricalMarkerMapper, CategoricalPatternMapper, ContinuousColorMapper,
        LinearColorMapper, LogColorMapper
    export Mapper, ColorMapper, CategoricalMapper, CategoricalColorMapper,
        CategoricalMarkerMapper, CategoricalPatternMapper, ContinuousColorMapper,
        LinearColorMapper, LogColorMapper
end


### GLYPHS

const Glyph = ModelType("Glyph")

const XYGlyph = ModelType("XYGlyph";
    inherits = [Glyph],
)

const ConnectedXYGlyph = ModelType("ConnectedXYGlyph";
    inherits = [XYGlyph],
)

const LineGlyph = ModelType("LineGlyph";
    inherits = [Glyph],
)

const FillGlyph = ModelType("FillGlyph";
    inherits = [Glyph],
)

const TextGlyph = ModelType("TextGlyph";
    inherits = [Glyph],
)

const HatchGlyph = ModelType("HatchGlyph";
    inherits = [Glyph],
)

const Marker = ModelType("Marker";
    inherits = [XYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :hit_dilation => FloatT(default=1.0),
        :size => SizeSpecT(default=4.0),
        :angle => AngleSpecT(default=0.0),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ],
)

const AnnularWedge = ModelType("AnnularWedge";
    inherits = [XYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :inner_radius => DistanceSpecT(default="inner_radius"),
        :outer_radius => DistanceSpecT(default="outer_radius"),
        :start_angle => AngleSpecT(default="start_angle"),
        :end_angle => AngleSpecT(default="end_angle"),
        :direction => DirectionT(default="anticlock"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Annulus = ModelType("Annulus";
    inherits = [XYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :inner_radius => DistanceSpecT(default="inner_radius"),
        :outer_radius => DistanceSpecT(default="outer_radius"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Arc = ModelType("Arc";
    inherits = [XYGlyph, LineGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :radius => DistanceSpecT(default="inner_radius"),
        :start_angle => AngleSpecT(default="start_angle"),
        :end_angle => AngleSpecT(default="end_angle"),
        :direction => DirectionT(default="anticlock"),
        LINE_PROPS,
    ]
)

const Bezier = ModelType("Bezier";
    inherits = [LineGlyph],
    props = [
        :x0 => NumberSpecT(default="x0"),
        :y0 => NumberSpecT(default="y0"),
        :x1 => NumberSpecT(default="x1"),
        :y1 => NumberSpecT(default="y1"),
        :cx0 => NumberSpecT(default="cx0"),
        :cy0 => NumberSpecT(default="cy0"),
        :cx1 => NumberSpecT(default="cx1"),
        :cy1 => NumberSpecT(default="cy1"),
        LINE_PROPS,
    ]
)

const Circle = ModelType("Circle";
    inherits = [Marker],
    props = [
        :radius => NullDistanceSpecT(),
        :radius_dimension => EnumT(Set(["x", "y", "max", "min"])),
    ]
)

const Ellipse = ModelType("Ellipse";
    inherits = [XYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :width => DistanceSpecT(default="width"),
        :height => DistanceSpecT(default="height"),
        :angle => AngleSpecT(default="angle"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const HArea = ModelType("HArea";
    inherits = [FillGlyph, HatchGlyph],
    props = [
        :x1 => NumberSpecT(default="x1"),
        :x2 => NumberSpecT(default="x2"),
        :y => NumberSpecT(default="y"),
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const HBar = ModelType("HBar";
    inherits = [LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :y => NumberSpecT(default="y"),
        :height => NumberSpecT(default="height"),
        :left => NumberSpecT(default="left"),
        :right => NumberSpecT(default="right"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const HexTile = ModelType("HexTile";
    inherits = [LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :size => FloatT(default=1.0),
        :r => NumberSpecT(default="r"),
        :q => NumberSpecT(default="q"),
        :scale => NumberSpecT(default="scale"),
        :orientation => StringT(default="pointytop"),
        LINE_PROPS,
        :line_color => DefaultT(nothing),
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Image = ModelType("Image";
    inherits = [XYGlyph],
    props = [
        :image => NumberSpecT(default="image"),
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :dw => DistanceSpecT(default="dw"),
        :dh => DistanceSpecT(default="dh"),
        :global_alpha => NumberSpecT(default=1.0),
        :dilate => BoolT(default=false),
        :color_mapper => InstanceT(ColorMapper, default=()->LinearColorMapper(palette="Greys9")),
    ]
)

const ImageRGBA = ModelType("ImageRGBA";
    inherits = [XYGlyph],
    props = [
        :image => NumberSpecT(default="image"),
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :dw => DistanceSpecT(default="dw"),
        :dh => DistanceSpecT(default="dh"),
        :global_alpha => NumberSpecT(default=1.0),
        :dilate => BoolT(default=false),
    ]
)

const ImageURL = ModelType("ImageURL";
    inherits = [XYGlyph],
    props = [
        :url => StringSpecT(default=Field("url")),
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :w => NullDistanceSpecT(default="w"),
        :h => NullDistanceSpecT(default="h"),
        :angle => AngleSpecT(default="angle"),
        :global_alpha => NumberSpecT(default=1.0),
        :dilate => BoolT(default=false),
        :anchor => AnchorT(),
        :retry_attempts => IntT(default=0),
        :retry_timeout => IntT(default=0),
    ]
)

const Line = ModelType("Line";
    inherits = [ConnectedXYGlyph, LineGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        SCALAR_LINE_PROPS,
    ],
)

const MultiLine = ModelType("MultiLine";
    inherits = [LineGlyph],
    props = [
        :xs => NumberSpecT(default="xs"),
        :ys => NumberSpecT(default="ys"),
        LINE_PROPS,
    ]
)

const MultiPolygons = ModelType("MultiPolygons";
    inherits = [LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :xs => NumberSpecT(default="xs"),
        :ys => NumberSpecT(default="ys"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Oval = ModelType("Oval";
    inherits = [XYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :width => DistanceSpecT(default="width"),
        :height => DistanceSpecT(default="height"),
        :angle => AngleSpecT(default="angle"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Patch = ModelType("Patch";
    inherits = [ConnectedXYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        SCALAR_LINE_PROPS,
        SCALAR_FILL_PROPS,
        SCALAR_HATCH_PROPS,
    ]
)

const Patches = ModelType("Patches";
    inherits = [XYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :xs => NumberSpecT(default="xs"),
        :ys => NumberSpecT(default="ys"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Quad = ModelType("Quad";
    inherits = [LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :left => NumberSpecT(default="left"),
        :right => NumberSpecT(default="right"),
        :bottom => NumberSpecT(default="bottom"),
        :top => NumberSpecT(default="top"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Quadratic = ModelType("Quadratic";
    inherits = [LineGlyph],
    props = [
        :x0 => NumberSpecT(default="x0"),
        :y0 => NumberSpecT(default="y0"),
        :x1 => NumberSpecT(default="x1"),
        :y1 => NumberSpecT(default="y1"),
        :cx => NumberSpecT(default="cx"),
        :cy => NumberSpecT(default="cy"),
        LINE_PROPS,
    ]
)

const Ray = ModelType("Ray";
    inherits = [XYGlyph, LineGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :angle => AngleSpecT(default=0.0),
        :length => DistanceSpecT(default=0.0),
        LINE_PROPS,
    ]
)

const Rect = ModelType("Rect";
    inherits = [XYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :width => DistanceSpecT(default="width"),
        :height => DistanceSpecT(default="height"),
        :angle => AngleSpecT(default=0.0),
        :dilate => BoolT(default=false),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Scatter = ModelType("Scatter";
    inherits = [Marker],
    props = [
        :marker => MarkerSpecT(default="circle"),
    ],
)

const Segment = ModelType("Segment";
    inherits = [LineGlyph],
    props = [
        :x0 => NumberSpecT(default="x0"),
        :y0 => NumberSpecT(default="y0"),
        :x1 => NumberSpecT(default="x1"),
        :y1 => NumberSpecT(default="y1"),
        LINE_PROPS,
    ]
)

const Step = ModelType("Step";
    inherits = [XYGlyph, LineGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        LINE_PROPS,
        :mode => StepModeT(default="before"),
    ]
)

const Text = ModelType("Text";
    inherits = [XYGlyph, TextGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :text => StringSpecT(default=Field("text")),
        :angle => AngleSpecT(default=0.0),
        :x_offset => NumberSpecT(default=0.0),
        :y_offset => NumberSpecT(default=0.0),
        TEXT_PROPS,
    ]
)

const VArea = ModelType("VArea";
    inherits = [FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y1 => NumberSpecT(default="y1"),
        :y2 => NumberSpecT(default="y2"),
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const VBar = ModelType("VBar";
    inherits = [LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :width => NumberSpecT(default=1.0),
        :bottom => NumberSpecT(default=0.0),
        :top => NumberSpecT(default="top"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

const Wedge = ModelType("Wedge";
    inherits = [XYGlyph, LineGlyph, FillGlyph, HatchGlyph],
    props = [
        :x => NumberSpecT(default="x"),
        :y => NumberSpecT(default="y"),
        :radius => DistanceSpecT(default="radius"),
        :start_angle => AngleSpecT(default="start_angle"),
        :end_angle => AngleSpecT(default="start_angle"),
        :direction => DirectionT(default="anticlock"),
        LINE_PROPS,
        FILL_PROPS,
        HATCH_PROPS,
    ]
)

module Glyphs
    import ..Bokeh: Glyph, XYGlyph, ConnectedXYGlyph, LineGlyph, FillGlyph, TextGlyph,
        HatchGlyph, Marker, AnnularWedge, Annulus, Arc, Bezier, Circle, Ellipse, HArea,
        HBar, HexTile, Image, ImageRGBA, ImageURL, Line, MultiLine, MultiPolygons, Oval,
        Patch, Patches, Quad, Quadratic, Ray, Rect, Scatter, Segment, Step, Text, VArea,
        VBar, Wedge
    export Glyph, XYGlyph, ConnectedXYGlyph, LineGlyph, FillGlyph, TextGlyph,
        HatchGlyph, Marker, AnnularWedge, Annulus, Arc, Bezier, Circle, Ellipse, HArea,
        HBar, HexTile, Image, ImageRGBA, ImageURL, Line, MultiLine, MultiPolygons, Oval,
        Patch, Patches, Quad, Quadratic, Ray, Rect, Scatter, Segment, Step, Text, VArea,
        VBar, Wedge
end


### RENERERS

const RendererGroup = ModelType("RendererGroup";
    props = [
        :visible => BoolT(default=true),
    ]
)

const Renderer = ModelType("Renderer";
    props = [
        :level => RenderLevelT(),
        :visible => BoolT() |> DefaultT(true),
        # :coordinates => NullableT(InstanceT(CoordinateMapping)), TODO
        :x_range_name => StringT(default="default"),
        :y_range_name => StringT(default="default"),
        :group => NullableT(InstanceT(RendererGroup)),
    ],
)

const TileRenderer = ModelType("TileRenderer";
    inherits = [Renderer],
    props = [
        # TODO
    ]
)

const DataRenderer = ModelType("DataRenderer";
    inherits = [Renderer],
    props = [
        :level => DefaultT("glyph"),
    ],
)

const GlyphRenderer = ModelType("GlyphRenderer";
    inherits = [DataRenderer],
    props = [
        :data_source => InstanceT(DataSource),
        :view => InstanceT(CDSView),
        :glyph => InstanceT(Glyph),
        :selection_glyph => NullableT(EitherT(AutoT(), InstanceT(Glyph)), default="auto"),
        :nonselection_glyph => NullableT(EitherT(AutoT(), InstanceT(Glyph)), default="auto"),
        :hover_glyph => NullableT(InstanceT(Glyph)),
        :muted_glyph => NullableT(EitherT(AutoT(), InstanceT(Glyph)), default="auto"),
        :muted => BoolT(default=false),
    ],
)

const GraphRenderer = ModelType("GraphRenderer";
    inherits = [DataRenderer],
    props = [
        # TODO
    ]
)

const GuideRenderer = ModelType("GuideRenderer";
    inherits = [Renderer],
    props = [
        :level => DefaultT("guide"),
    ]
)

module Renderers
    import ..Bokeh: RendererGroup, Renderer, TileRenderer, DataRenderer, GlyphRenderer,
        GraphRenderer, GuideRenderer
    export RendererGroup, Renderer, TileRenderer, DataRenderer, GlyphRenderer,
        GraphRenderer, GuideRenderer
end


### LABELING

const LabelingPolicy = ModelType("LabelingPolicy")

const AllLabels = ModelType("LabelingPolicy";
    inherits = [LabelingPolicy],
)

const NoOverlap = ModelType("NoOverlap";
    inherits = [LabelingPolicy],
    props = [
        :min_distance => IntT(default=5),
    ]
)

const CustomLabelingPolicy = ModelType("CustomLabelingPolicy";
    inherits = [LabelingPolicy],
)

module Labels
    import ..Bokeh: LabelingPolicy, AllLabels, NoOverlap, CustomLabelingPolicy
    export LabelingPolicy, AllLabels, NoOverlap, CustomLabelingPolicy
end


### AXES

const Axis = ModelType("Axis";
    inherits = [GuideRenderer],
    props = [
        :bounds => EitherT(AutoT(), TupleT(FloatT(), FloatT())), # TODO datetime
        :ticker => TickerT(),
        :formatter => InstanceT(TickFormatter),
        :axis_label => NullableT(StringT()),
        :axis_label_standoff => IntT(default=5),
        :axis_label => SCALAR_TEXT_PROPS,
        :axis_label_text_font_size => DefaultT("13px"),
        :axis_label_text_font_style => DefaultT("italic"),
        :major_label_standoff => IntT(default=5),
        :major_label_orientation => EitherT(OrientationT(), FloatT()),
        :major_label_overrides => DictT(EitherT(FloatT(), StringT()), TextLikeT()),
        :major_label_policy => InstanceT(LabelingPolicy, default=()->AllLabels()),
        :major_label => SCALAR_TEXT_PROPS,
        :major_label_text_align => DefaultT("center"),
        :major_label_text_baseline => DefaultT("alphabetic"),
        :major_label_text_font_size => DefaultT("11px"),
        :axis => SCALAR_LINE_PROPS,
        :major_tick => SCALAR_LINE_PROPS,
        :major_tick_in => IntT(default=2),
        :major_tick_out => IntT(default=6),
        :minor_tick => SCALAR_LINE_PROPS,
        :minor_tick_in => IntT(default=0),
        :minor_tick_out => IntT(default=4),
        :fixed_location => EitherT(NullT(), FloatT(), FactorT()),
    ],
)

const ContinuousAxis = ModelType("ContinuousAxis";
    inherits = [Axis],
)

const LinearAxis = ModelType("LinearAxis";
    inherits = [ContinuousAxis],
    props = [
        :ticker => DefaultT(()->BasicTicker()),
        :formatter => DefaultT(()->BasicTickFormatter()),
    ]
)

const LogAxis = ModelType("LogAxis";
    inherits = [ContinuousAxis],
    props = [
        :ticker => DefaultT(()->LogTicker()),
        :formatter => DefaultT(()->LogTickFormatter()),
    ]
)

const CategoricalAxis = ModelType("CategoricalAxis";
    inherits = [Axis],
    props = [
        :ticker => DefaultT(()->CategoricalTicker()),
        :formatter => DefaultT(()->CategoricalTickFormatter()),
        :separator => SCALAR_LINE_PROPS,
        :separator_line_color => DefaultT("lightgrey"),
        :separator_line_width => DefaultT(2),
        :group => SCALAR_TEXT_PROPS,
        :group_label_orientation => EitherT(TickLabelOrientationT(), FloatT(), default="parallel"),
        :group_text_font_size => DefaultT("11px"),
        :group_text_font_style => DefaultT("bold"),
        :group_text_color => DefaultT("grey"),
        :subgroup => SCALAR_TEXT_PROPS,
        :subgroup_label_orientation => EitherT(TickLabelOrientationT(), FloatT(), default="parallel"),
        :subgroup_text_font_size => DefaultT("11px"),
        :subgroup_text_font_style => DefaultT("bold"),
    ]
)

const DatetimeAxis = ModelType("DatetimeAxis";
    inherits = [LinearAxis],
    props = [
        :ticker => DefaultT(()->DatetimeTicker()),
        :formatter => DefaultT(()->DatetimeTickFormatter()),
    ]
)

const MercatorAxis = ModelType("MercatorAxis";
    # TODO: the python constructor has a "dimension" argument which sets the dimension on
    # the ticker and formatter
    inherits = [LinearAxis],
    props = [
        :ticker => DefaultT(()->MercatorTicker()),
        :formatter => DefaultT(()->MercatorTickFormatter()),
    ]
)

module Axes
    import ..Bokeh: Axis, ContinuousAxis, LinearAxis, LogAxis, CategoricalAxis,
        DatetimeAxis, MercatorAxis
    export Axis, ContinuousAxis, LinearAxis, LogAxis, CategoricalAxis,
        DatetimeAxis, MercatorAxis
end


### RANGES

const Range = ModelType("Range")

const Range1d = ModelType("Range1d";
    inherits = [Range],
    props = [
        :start => FloatT() |> DefaultT(0.0),
        :end => FloatT() |> DefaultT(1.0),
        :reset_start => EitherT(NullT(), FloatT()) |> DefaultT(nothing),
        :reset_end => EitherT(NullT(), FloatT()) |> DefaultT(nothing),
    ],
)

const DataRange = ModelType("DataRange";
    inherits = [Range],
)

const DataRange1d = ModelType("DataRange1d";
    inherits = [Range1d, DataRange],
    props = [
        :range_padding => FloatT(default=0.1),
        :start => EitherT(NullT(), FloatT()),
        :end => EitherT(NullT(), FloatT()),
    ]
)

const FactorRange = ModelType("FactorRange";
    inherits = [Range],
    props = [
        :factors => FactorSeqT(),
    ],
)

module Ranges
    import ..Bokeh: Range, Range1d, DataRange, DataRange1d, FactorRange
    export Range, Range1d, DataRange, DataRange1d, FactorRange
end


### SCALES

const Scale = ModelType("Scale";
    inherits = [Transform],
)

const ContinuousScale = ModelType("ContinuousScale";
    inherits = [Scale],
)

const LinearScale = ModelType("LinearScale";
    inherits = [ContinuousScale],
)

const LogScale = ModelType("LogScale";
    inherits = [ContinuousScale],
)

const CategoricalScale = ModelType("CategoricalScale";
    inherits = [Scale],
)

module Scales
    import ..Bokeh: Scale, ContinuousScale, LinearScale, LogScale, CategoricalScale
    export Scale, ContinuousScale, LinearScale, LogScale, CategoricalScale
end


### GRIDS

const Grid = ModelType("Grid";
    inherits = [GuideRenderer],
    props = [
        :dimension => IntT() |> DefaultT(0),
        :axis => InstanceT(Axis) |> NullableT,
        :grid => SCALAR_LINE_PROPS,
        :grid_line_color => DefaultT("#e5e5e5"),
        :minor_grid => SCALAR_LINE_PROPS,
        :minor_grid_line_color => DefaultT(nothing),
        :band => SCALAR_FILL_PROPS,
        :band_fill_alpha => DefaultT(0),
        :band_fill_color => DefaultT(nothing),
        :band => SCALAR_HATCH_PROPS,
        :level => DefaultT("underlay"),
    ],
)

module Grids
    import ..Bokeh: Grid
    export Grid
end


### ANNOTATIONS

const Annotation = ModelType("Renderer";
    inherits = [Renderer],
    props = [
        :level => DefaultT("annotation"),
    ]
)

const TextAnnotation = ModelType("TextAnnotation";
    inherits = [Annotation],
)

const Title = ModelType("Title";
    inherits = [TextAnnotation],
    props = [
        :text => StringT(default=""),
    ]
)

const LegendItem = ModelType("LegendItem";
    props = [
        :label => NullStringSpecT(),
        :renderers => ListT(InstanceT(GlyphRenderer)),
        :index => NullableT(IntT()),
        :visible => BoolT(default=true),
    ]
)

const Legend = ModelType("Legend",
    inherits = [Annotation],
    props = [
        :location => EitherT(LegendLocationT(), TupleT(FloatT(), FloatT()), default="top_right"),
        :orientation => OrientationT(default="vertical"),
        :title => NullableT(StringT()),
        :title => SCALAR_TEXT_PROPS,
        :title_text_font_size => DefaultT("13px"),
        :title_text_font_style => DefaultT("italic"),
        :title_standoff => IntT(default=5),
        :border => SCALAR_LINE_PROPS,
        :border_line_color => DefaultT("#e5e5e5"),
        :border_line_alpha => DefaultT(0.5),
        :background => SCALAR_FILL_PROPS,
        :inactive => SCALAR_FILL_PROPS,
        :click_policy => LegendClickPolicyT(default="none"),
        :background_fill_color => DefaultT("#ffffff"),
        :background_fill_alpha => DefaultT(0.95),
        :inactive_fill_color => DefaultT("white"),
        :inactive_fill_alpha => DefaultT(0.7),
        :label => SCALAR_TEXT_PROPS,
        :label_text_baseline => DefaultT("middle"),
        :label_text_font_size => DefaultT("13px"),
        :label_standoff => IntT(default=5),
        :label_height => IntT(default=20),
        :label_width => IntT(default=20),
        :glyph_height => IntT(default=20),
        :glyph_width => IntT(default=20),
        :margin => IntT(default=10),
        :padding => IntT(default=10),
        :spacing => IntT(default=3),
        :items => ListT(InstanceT(LegendItem)),
    ]
)

module Annotations
    import ..Bokeh: Annotation, TextAnnotation, Title, LegendItem, Legend
    export Annotation, TextAnnotation, Title, LegendItem, Legend
end


### TOOLS

const Tool = ModelType("Tool")

const ActionTool = ModelType("ActionTool";
    inherits = [Tool],
)

const GestureTool = ModelType("GestureTool";
    inherits = [Tool],
)

const Drag = ModelType("Drag";
    inherits = [GestureTool],
)

const Scroll = ModelType("Scroll";
    inherits = [GestureTool],
)

const Tap = ModelType("Tap";
    inherits = [GestureTool],
)

const SelectTool = ModelType("SelectTool";
    inherits = [GestureTool],
)

const InspectTool = ModelType("InspectTool";
    inherits = [GestureTool],
)

const PanTool = ModelType("PanTool";
    inherits = [Drag],
)

const RangeTool = ModelType("RangeTool";
    inherits = [Drag],
)

const WheelPanTool = ModelType("WheelPanTool";
    inherits = [Scroll],
)

const WheelZoomTool = ModelType("WheelZoomTool";
    inherits = [Scroll],
)

const CustomAction = ModelType("CustomAction";
    inherits = [ActionTool],
)

const SaveTool = ModelType("SaveTool";
    inherits = [ActionTool],
)

const ResetTool = ModelType("ResetTool";
    inherits = [ActionTool],
)

const TapTool = ModelType("TapTool";
    inherits = [Tap, SelectTool],
)

const CrosshairTool = ModelType("CrosshairTool";
    inherits = [InspectTool],
)

const BoxZoomTool = ModelType("BoxZoomTool";
    inherits = [Drag],
)

const ZoomInTool = ModelType("ZoomInTool";
    inherits = [ActionTool],
)

const ZoomOutTool = ModelType("ZoomOutTool";
    inherits = [ActionTool],
)

const BoxSelectTool = ModelType("BoxSelectTool";
    inherits = [Drag, SelectTool],
)

const LassoSelectTool = ModelType("LassoSelectTool";
    inherits = [Drag, SelectTool],
)

const PolySelectTool = ModelType("PolySelectTool";
    inherits = [Tap, SelectTool],
)

const CustomJSHover = ModelType("CustomJSHover")

const HoverTool = ModelType("HoverTool";
    inherits = [InspectTool],
    props = [
        :names => ListT(StringT()),
        :renderers => EitherT(AutoT(), ListT(InstanceT(DataRenderer)), default="auto"),
        # :callback => NullableT(CallbackT()), TODO
        :tooltips => EitherT(
            NullT(),
            # InstanceT(TemplateT()), TODO
            StringT(),
            ListT(TupleT(StringT(), StringT())),
            default = [
                ("index", "\$index"),
                ("data (x, y)", "(\$x, \$y)"),
                ("screen (x, y)", "(\$sx, \$sy)"),
            ],
            result_type = Any,
        )
    ]
)

const HelpTool = ModelType("HelpTool";
    inherits = [ActionTool]
)

const UndoTool = ModelType("UndoTool";
    inherits = [ActionTool]
)

const RedoTool = ModelType("RedoTool";
    inherits = [ActionTool]
)

const EditTool = ModelType("EditTool";
    inherits = [GestureTool]
)

const PolyTool = ModelType("PolyTool";
    inherits = [EditTool]
)

const BoxEditTool = ModelType("BoxEditTool";
    inherits = [EditTool, Drag, Tap]
)

const PointDrawTool = ModelType("PointDrawTool";
    inherits = [EditTool, Drag, Tap]
)

const PolyDrawTool = ModelType("PolyDrawTool";
    inherits = [PolyTool, Drag, Tap],
)

const FreehandDrawTool = ModelType("FreehandDrawTool";
    inherits = [EditTool, Drag, Tap],
)

const PolyEditTool = ModelType("PolyEditTool";
    inherits = [PolyTool, Drag, Tap],
)

const LineEditTool = ModelType("LineEditTool";
    inherits = [EditTool, Drag, Tap],
)

module Tools
    import ..Bokeh: Tool, ActionTool, GestureTool, Drag, Scroll, Tap, SelectTool,
        InspectTool, PanTool, RangeTool, WheelPanTool, WheelZoomTool, CustomAction,
        SaveTool, ResetTool, TapTool, CrosshairTool, BoxZoomTool, ZoomInTool, ZoomOutTool,
        BoxSelectTool, LassoSelectTool, PolySelectTool, CustomJSHover, HoverTool, HelpTool,
        UndoTool, RedoTool, EditTool, PolyTool, BoxEditTool, PointDrawTool, PolyDrawTool,
        FreehandDrawTool, PolyEditTool, LineEditTool
    export Tool, ActionTool, GestureTool, Drag, Scroll, Tap, SelectTool,
        InspectTool, PanTool, RangeTool, WheelPanTool, WheelZoomTool, CustomAction,
        SaveTool, ResetTool, TapTool, CrosshairTool, BoxZoomTool, ZoomInTool, ZoomOutTool,
        BoxSelectTool, LassoSelectTool, PolySelectTool, CustomJSHover, HoverTool, HelpTool,
        UndoTool, RedoTool, EditTool, PolyTool, BoxEditTool, PointDrawTool, PolyDrawTool,
        FreehandDrawTool, PolyEditTool, LineEditTool
end



### TOOLBAR

const ToolbarBase = ModelType("ToolbarBase";
    props = [
        :logo => NullableT(EnumT(Set(["normal", "grey"])), default="normal"),
        :autohide => BoolT(default=false),
        :tools => ListT(InstanceT(Tool)),
    ]
)

const Toolbar = ModelType("Toolbar";
    inherits = [ToolbarBase],
    props = [
        :active_drag => EitherT(NullT(), AutoT(), InstanceT(Drag), default="auto"),
        :active_inspect => EitherT(NullT(), AutoT(), InstanceT(InspectTool), SeqT(InstanceT(InspectTool)), default="auto"),
        :active_scroll => EitherT(NullT(), AutoT(), InstanceT(Scroll), default="auto"),
        :active_tap => EitherT(NullT(), AutoT(), InstanceT(Tap), default="auto"),
        :active_multi => EitherT(NullT(), AutoT(), InstanceT(GestureTool), default="auto"),
    ]
)

const ProxyToolbar = ModelType("ProxyToolbar";
    inherits = [ToolbarBase],
    props = [
        :toolbars => ListT(InstanceT(Toolbar)),
    ]
)

const ToolbarBox = ModelType("ToolbarBox";
    inherits = [LayoutDOM],
    props = [
        :toolbar_location => LocationT(default="right"),
    ],
)

module Toolbars
    import ..Bokeh: ToolbarBase, Toolbar, ProxyToolbar, ToolbarBox
    export ToolbarBase, Toolbar, ProxyToolbar, ToolbarBox
end

### PLOT

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

const Plot = ModelType("Plot";
    inherits = [LayoutDOM],
    props = [
        :x_range => InstanceT(Range, default=()->DataRange1d()),
        :y_range => InstanceT(Range, default=()->DataRange1d()),
        :x_scale => InstanceT(Scale, default=()->LinearScale()),
        :y_scale => InstanceT(Scale, default=()->LinearScale()),
        :extra_x_ranges => DictT(StringT(), InstanceT(Range)),
        :extra_y_ranges => DictT(StringT(), InstanceT(Range)),
        :extra_x_scales => DictT(StringT(), InstanceT(Scale)),
        :extra_y_scales => DictT(StringT(), InstanceT(Scale)),
        :hidpi => BoolT(default=true),
        :title => NullableT(TitleT(), default=()->Title()),
        :title_location => NullableT(LocationT(), default="above"),
        :outline => SCALAR_LINE_PROPS,
        :outline_line_color => DefaultT("#e5e5e5"),
        :renderers => ListT(InstanceT(Renderer)),
        :toolbar => InstanceT(Toolbar, default=()->Toolbar()),
        :toolbar_location => NullableT(LocationT(), default="right"),
        :toolbar_sticky => BoolT(default=true),
        :left => ListT(InstanceT(Renderer)),
        :right => ListT(InstanceT(Renderer)),
        :above => ListT(InstanceT(Renderer)),
        :below => ListT(InstanceT(Renderer)),
        :center => ListT(InstanceT(Renderer)),
        :width => NullableT(IntT(), default=600),
        :height => NullableT(IntT(), default=600),
        :frame_width => NullableT(IntT()),
        :frame_height => NullableT(IntT()),
        # :inner_width => PropType(Any; default=nothing),
        # :inner_height => PropType(Any; default=nothing),
        # :outer_width => PropType(Any; default=nothing),
        # :outer_height => PropType(Any; default=nothing),
        :background => SCALAR_FILL_PROPS,
        :background_fill_color => DefaultT("#ffffff"),
        :border => SCALAR_FILL_PROPS,
        :border_fill_color => DefaultT("#ffffff"),
        :min_border_top => NullableT(IntT()),
        :min_border_bottom => NullableT(IntT()),
        :min_border_left => NullableT(IntT()),
        :min_border_right => NullableT(IntT()),
        :min_border => NullableT(IntT(), default=5),
        :lod_factor => IntT(default=10),
        :lod_threshold => NullableT(IntT(), default=2000),
        :lod_interval => IntT(default=300),
        :lod_timeout => IntT(default=500),
        :output_backend => OutputBackendT(default="canvas"),
        :match_aspect => BoolT(default=false),
        :aspect_scale => FloatT(default=1.0),
        :reset_policy => ResetPolicyT(default="standard"),

        # getters/setters
        :x_axis => GetSetT(plot_get_renderer(type=Axis, sides=[:below,:above], plural=:x_axes)),
        :y_axis => GetSetT(plot_get_renderer(type=Axis, sides=[:left,:right], plural=:y_axes)),
        :axis => GetSetT(plot_get_renderer(type=Axis, sides=[:below,:left,:above,:right], plural=:axes)),
        :x_axes => GetSetT(plot_get_renderers(type=Axis, sides=[:below,:above])),
        :y_axes => GetSetT(plot_get_renderers(type=Axis, sides=[:left,:right])),
        :axes => GetSetT(plot_get_renderers(type=Axis, sides=[:below,:left,:above,:right])),
        :x_grid => GetSetT(plot_get_renderer(type=Grid, sides=[:center], filter=m->m.dimension==0, plural=:x_grids)),
        :y_grid => GetSetT(plot_get_renderer(type=Grid, sides=[:center], filter=m->m.dimension==1, plural=:y_grids)),
        :grid => GetSetT(plot_get_renderer(type=Grid, sides=[:center], plural=:grids)),
        :x_grids => GetSetT(plot_get_renderers(type=Grid, sides=[:center], filter=m->m.dimension==0)),
        :y_grids => GetSetT(plot_get_renderers(type=Grid, sides=[:center], filter=m->m.dimension==1)),
        :grids => GetSetT(plot_get_renderers(type=Grid, sides=[:center])),
        :legend => GetSetT(plot_get_renderer(type=Legend, sides=[:below,:left,:above,:right,:center], plural=:legends)),
        :legends => GetSetT(plot_get_renderers(type=Legend, sides=[:below,:left,:above,:right,:center])),
        :tools => GetSetT((m)->(m.toolbar.tools), (m,v)->(m.toolbar.tools=v)),
        :ranges => GetSetT(m->PropVector([m.x_range::Model, m.y_range::Model])),
        :scales => GetSetT(m->PropVector([m.x_scale::Model, m.y_scale::Model])),
    ],
)


### FIGURE

const Figure = ModelType("Plot", "Figure";
    inherits = [Plot],
)
