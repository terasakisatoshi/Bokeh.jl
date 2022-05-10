const TickFormatter = ModelType("TickFormatter";
    abstract = true,
)

const BasicTickFormatter = ModelType("BasicTickFormatter";
    bases = [TickFormatter],
    props = [
        :precision => EitherT(AutoT(), IntT()),
        :use_scientific => BoolT(default=true),
        :power_limit_high => IntT(default=5),
        :power_limit_low => IntT(default=-3),
    ]
)

const MercatorTickFormatter = ModelType("MercatorTickFormatter";
    bases = [BasicTickFormatter],
    props = [
        :dimension => NullableT(LatLonT()),
    ]
)

const NumericalTickFormatter = ModelType("NumericalTickFormatter";
    bases = [TickFormatter],
    props = [
        :format => StringT(default="0,0"),
        :language => NumeralLanguageT(default="en"),
        :rounding => RoundingFunctionT(),
    ]
)

const PrintfTickFormatter = ModelType("PrintfTickFormatter";
    bases = [TickFormatter],
    props = [
        :format => StringT(default="%s"),
    ]
)

const LogTickFormatter = ModelType("LogTickFormatter";
    bases = [TickFormatter],
    props = [
        :ticker => NullableT(InstanceT(Ticker)),
        :min_exponent => IntT(default=0),
    ]
)

const CategoricalTickFormatter = ModelType("CategoricalTickFormatter";
    bases = [TickFormatter],
)

const FuncTickFormatter = ModelType("FuncTickFormatter";
    bases = [TickFormatter],
    props = [
        # TODO
    ]
)

const DatetimeTickFormatter = ModelType("DatetimeTickFormatter";
    bases = [TickFormatter],
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