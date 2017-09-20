__precompile__(true)

module ColorVectorSpace

using Colors, FixedPointNumbers, Compat
import StatsBase: histrange

import Base: ==, +, -, *, /, ^, <, ~
import Base: abs, abs2, clamp, convert, copy, div, eps, isfinite, isinf,
    isnan, isless, length, mapreduce, norm, oneunit, promote_array_type,
    promote_op, promote_rule, zero, trunc, floor, round, ceil, bswap,
    mod, rem, atan2, hypot, max, min, varm, real, typemin, typemax

export nan

# The unaryOps
import Base:      conj, sin, cos, tan, sinh, cosh, tanh,
                  asin, acos, atan, asinh, acosh, atanh,
                  sec, csc, cot, asec, acsc, acot,
                  sech, csch, coth, asech, acsch, acoth,
                  sinc, cosc, cosd, cotd, cscd, secd,
                  sind, tand, acosd, acotd, acscd, asecd,
                  asind, atand, rad2deg, deg2rad,
                  log, log2, log10, log1p, exponent, exp,
                  exp2, expm1, cbrt, sqrt, erf,
                  erfc, erfcx, erfi, dawson,
                  significand, lgamma,
                  gamma, lfact, frexp, modf, airy, airyai,
                  airyprime, airyaiprime, airybi, airybiprime,
                  besselj0, besselj1, bessely0, bessely1,
                  eta, zeta, digamma, float, middle

export dotc

AbstractGray{T} = Color{T,1}
TransparentRGB{C<:AbstractRGB,T}   = TransparentColor{C,T,4}
TransparentGray{C<:AbstractGray,T} = TransparentColor{C,T,2}
TransparentRGBFloat{C<:AbstractRGB,T<:AbstractFloat} = TransparentColor{C,T,4}
TransparentGrayFloat{C<:AbstractGray,T<:AbstractFloat} = TransparentColor{C,T,2}
TransparentRGBNormed{C<:AbstractRGB,T<:Normed} = TransparentColor{C,T,4}
TransparentGrayNormed{C<:AbstractGray,T<:Normed} = TransparentColor{C,T,2}

MathTypes{T,C} = Union{AbstractRGB{T},TransparentRGB{C,T},AbstractGray{T},TransparentGray{C,T}}

# convert(RGB{Float32}, NaN) doesn't and shouldn't work, so we need to reintroduce nan
nan(::Type{T}) where {T<:AbstractFloat} = convert(T, NaN)
nan(::Type{C}) where {C<:MathTypes} = _nan(eltype(C), C)
_nan(::Type{T}, ::Type{C}) where {T<:AbstractFloat,C<:AbstractGray} = (x = convert(T, NaN); C(x))
_nan(::Type{T}, ::Type{C}) where {T<:AbstractFloat,C<:TransparentGray} = (x = convert(T, NaN); C(x,x))
_nan(::Type{T}, ::Type{C}) where {T<:AbstractFloat,C<:AbstractRGB} = (x = convert(T, NaN); C(x,x,x))
_nan(::Type{T}, ::Type{C}) where {T<:AbstractFloat,C<:TransparentRGB} = (x = convert(T, NaN); C(x,x,x,x))

## Generic algorithms
mapreduce(f, op::Union{typeof(&), typeof(|)}, a::MathTypes) = f(a)  # ambiguity
mapreduce(f, op, a::MathTypes) = f(a)
Base.r_promote(::typeof(+), c::MathTypes) = mapc(x->Base.r_promote(+, x), c)

for f in (:trunc, :floor, :round, :ceil, :eps, :bswap)
    @eval $f(g::Gray{T}) where {T} = Gray{T}($f(gray(g)))
    @eval Compat.@dep_vectorize_1arg Gray $f
end
eps(::Type{Gray{T}}) where {T} = Gray(eps(T))
Compat.@dep_vectorize_1arg AbstractGray isfinite
Compat.@dep_vectorize_1arg AbstractGray isinf
Compat.@dep_vectorize_1arg AbstractGray isnan
Compat.@dep_vectorize_1arg AbstractGray abs
Compat.@dep_vectorize_1arg AbstractGray abs2
for f in (:trunc, :floor, :round, :ceil)
    @eval $f(::Type{T}, g::Gray) where {T<:Integer} = Gray{T}($f(T, gray(g)))
end

for f in (:mod, :rem, :mod1)
    @eval $f(x::Gray, m::Gray) = Gray($f(gray(x), gray(m)))
end

# Real values are treated like grays
ColorTypes.gray(x::Real) = x

dotc(x::T, y::T) where {T<:Real} = acc(x)*acc(y)
dotc(x::Real, y::Real) = dotc(promote(x, y)...)

# Return types for arithmetic operations
multype(::Type{A}, ::Type{B}) where {A,B} = coltype(typeof(zero(A)*zero(B)))
sumtype(::Type{A}, ::Type{B}) where {A,B} = coltype(typeof(zero(A)+zero(B)))
divtype(::Type{A}, ::Type{B}) where {A,B} = coltype(typeof(zero(A)/oneunit(B)))
powtype(::Type{A}, ::Type{B}) where {A,B} = coltype(typeof(zero(A)^zero(B)))
multype(a::Colorant, b::Colorant) = multype(eltype(a),eltype(b))
sumtype(a::Colorant, b::Colorant) = sumtype(eltype(a),eltype(b))
divtype(a::Colorant, b::Colorant) = divtype(eltype(a),eltype(b))
powtype(a::Colorant, b::Colorant) = powtype(eltype(a),eltype(b))

coltype(::Type{T}) where {T<:Fractional} = T
coltype(::Type{T}) where {T}             = Float64

acctype(::Type{T}) where {T<:FixedPoint} = FixedPointNumbers.floattype(T)
acctype(::Type{T}) where {T<:Number} = T

acc(x::Number) = convert(acctype(typeof(x)), x)

# Scalar binary RGB operations require the same RGB type for each element,
# otherwise we don't know which to return
color_rettype(::Type{A}, ::Type{B}) where {A<:AbstractRGB,B<:AbstractRGB} = _color_rettype(base_colorant_type(A), base_colorant_type(B))
color_rettype(::Type{A}, ::Type{B}) where {A<:AbstractGray,B<:AbstractGray} = _color_rettype(base_colorant_type(A), base_colorant_type(B))
color_rettype(::Type{A}, ::Type{B}) where {A<:TransparentRGB,B<:TransparentRGB} = _color_rettype(base_colorant_type(A), base_colorant_type(B))
color_rettype(::Type{A}, ::Type{B}) where {A<:TransparentGray,B<:TransparentGray} = _color_rettype(base_colorant_type(A), base_colorant_type(B))
_color_rettype(::Type{A}, ::Type{B}) where {A<:Colorant,B<:Colorant} = error("binary operation with $A and $B, return type is ambiguous")
_color_rettype(::Type{C}, ::Type{C}) where {C<:Colorant} = C

color_rettype(c1::Colorant, c2::Colorant) = color_rettype(typeof(c1), typeof(c2))

arith_colorant_type(::C) where {C<:Colorant} = arith_colorant_type(C)
arith_colorant_type(::Type{C}) where {C<:Colorant} = base_colorant_type(C)
arith_colorant_type(::Type{Gray24}) = Gray
arith_colorant_type(::Type{AGray32}) = AGray
arith_colorant_type(::Type{RGB24}) = RGB
arith_colorant_type(::Type{ARGB32}) = ARGB

## Math on Colors. These implementations encourage inlining and,
## for the case of Normed types, nearly halve the number of multiplications (for RGB)

# Scalar RGB
copy(c::AbstractRGB) = c
(+)(c::AbstractRGB) = mapc(+, c)
(+)(c::TransparentRGB) = mapc(+, c)
(-)(c::AbstractRGB) = mapc(-, c)
(-)(c::TransparentRGB) = mapc(-, c)
(*)(f::Real, c::AbstractRGB) = arith_colorant_type(c){multype(typeof(f),eltype(c))}(f*red(c), f*green(c), f*blue(c))
(*)(f::Real, c::TransparentRGB) = arith_colorant_type(c){multype(typeof(f),eltype(c))}(f*red(c), f*green(c), f*blue(c), f*alpha(c))
function (*)(f::Real, c::AbstractRGB{T}) where T<:Normed
    fs = f*(1/reinterpret(oneunit(T)))
    arith_colorant_type(c){multype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
function (*)(f::Normed, c::AbstractRGB{T}) where T<:Normed
    fs = reinterpret(f)*(1/widen(reinterpret(oneunit(T)))^2)
    arith_colorant_type(c){multype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
function (/)(c::AbstractRGB{T}, f::Real) where T<:Normed
    fs = (one(f)/reinterpret(oneunit(T)))/f
    arith_colorant_type(c){divtype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
function (/)(c::AbstractRGB{T}, f::Integer) where T<:Normed
    fs = (1/reinterpret(oneunit(T)))/f
    arith_colorant_type(c){divtype(typeof(f),T)}(fs*reinterpret(red(c)), fs*reinterpret(green(c)), fs*reinterpret(blue(c)))
end
(+)(a::AbstractRGB{S}, b::AbstractRGB{T}) where {S,T} = color_rettype(a, b){sumtype(S,T)}(red(a)+red(b), green(a)+green(b), blue(a)+blue(b))
(-)(a::AbstractRGB{S}, b::AbstractRGB{T}) where {S,T} = color_rettype(a, b){sumtype(S,T)}(red(a)-red(b), green(a)-green(b), blue(a)-blue(b))
(+)(a::TransparentRGB, b::TransparentRGB) =
    color_rettype(a, b){sumtype(a,b)}(red(a)+red(b), green(a)+green(b), blue(a)+blue(b), alpha(a)+alpha(b))
(-)(a::TransparentRGB, b::TransparentRGB) =
    color_rettype(a, b){sumtype(a,b)}(red(a)-red(b), green(a)-green(b), blue(a)-blue(b), alpha(a)-alpha(b))
(*)(c::AbstractRGB, f::Real) = (*)(f, c)
(*)(c::TransparentRGB, f::Real) = (*)(f, c)
(/)(c::AbstractRGB, f::Real) = (one(f)/f)*c
(/)(c::TransparentRGB, f::Real) = (one(f)/f)*c
(/)(c::AbstractRGB, f::Integer) = (one(eltype(c))/f)*c
(/)(c::TransparentRGB, f::Integer) = (one(eltype(c))/f)*c

isfinite(c::Colorant{T}) where {T<:Normed} = true
isfinite(c::Colorant) = mapreducec(isfinite, &, true, c)
isnan(c::Colorant{T}) where {T<:Normed} = false
isnan(c::Colorant) = mapreducec(isnan, |, false, c)
isinf(c::Colorant{T}) where {T<:Normed} = false
isinf(c::Colorant) = mapreducec(isinf, |, false, c)
abs(c::AbstractRGB) = abs(red(c))+abs(green(c))+abs(blue(c)) # should this have a different name?
abs(c::AbstractRGB{T}) where {T<:Normed} = Float32(red(c))+Float32(green(c))+Float32(blue(c)) # should this have a different name?
abs(c::TransparentRGB) = abs(red(c))+abs(green(c))+abs(blue(c))+abs(alpha(c)) # should this have a different name?
abs(c::TransparentRGB{T}) where {T<:Normed} = Float32(red(c))+Float32(green(c))+Float32(blue(c))+Float32(alpha(c)) # should this have a different name?
abs2(c::AbstractRGB) = red(c)^2+green(c)^2+blue(c)^2
abs2(c::AbstractRGB{T}) where {T<:Normed} = Float32(red(c))^2+Float32(green(c))^2+Float32(blue(c))^2
abs2(c::TransparentRGB) = (ret = abs2(color(c)); ret + convert(typeof(ret), alpha(c))^2)
norm(c::AbstractRGB) = sqrt(abs2(c))
norm(c::TransparentRGB) = sqrt(abs2(c))

oneunit(::Type{C}) where {C<:AbstractRGB}     = C(1,1,1)
oneunit(::Type{C}) where {C<:TransparentRGB}  = C(1,1,1,1)

zero(::Type{C}) where {C<:AbstractRGB}    = C(0,0,0)
zero(::Type{C}) where {C<:TransparentRGB} = C(0,0,0,0)
zero(::Type{C}) where {C<:YCbCr} = C(0,0,0)
zero(::Type{C}) where {C<:HSV} = C(0,0,0)
oneunit(p::Colorant) = oneunit(typeof(p))
Base.one(c::Colorant) = Base.one(typeof(c))
zero(p::Colorant) = zero(typeof(p))

# These constants come from squaring the conversion to grayscale
# (rec601 luma), and normalizing
dotc(x::T, y::T) where {T<:AbstractRGB} = 0.200f0 * acc(red(x))*acc(red(y)) + 0.771f0 * acc(green(x))*acc(green(y)) + 0.029f0 * acc(blue(x))*acc(blue(y))
dotc(x::AbstractRGB, y::AbstractRGB) = dotc(promote(x, y)...)

# Scalar Gray
copy(c::AbstractGray) = c
const unaryOps = (:~, :conj, :abs,
                  :sin, :cos, :tan, :sinh, :cosh, :tanh,
                  :asin, :acos, :atan, :asinh, :acosh, :atanh,
                  :sec, :csc, :cot, :asec, :acsc, :acot,
                  :sech, :csch, :coth, :asech, :acsch, :acoth,
                  :sinc, :cosc, :cosd, :cotd, :cscd, :secd,
                  :sind, :tand, :acosd, :acotd, :acscd, :asecd,
                  :asind, :atand, :rad2deg, :deg2rad,
                  :log, :log2, :log10, :log1p, :exponent, :exp,
                  :exp2, :expm1, :cbrt, :sqrt, :erf,
                  :erfc, :erfcx, :erfi, :dawson,
                  :significand, :lgamma,
                  :gamma, :lfact, :frexp, :modf, :airy, :airyai,
                  :airyprime, :airyaiprime, :airybi, :airybiprime,
                  :besselj0, :besselj1, :bessely0, :bessely1,
                  :eta, :zeta, :digamma)
for op in unaryOps
    @eval ($op)(c::AbstractGray) = $op(gray(c))
end

middle(c::AbstractGray) = arith_colorant_type(c)(middle(gray(c)))
middle(x::C, y::C) where {C<:AbstractGray} = arith_colorant_type(C)(middle(gray(x), gray(y)))

(*)(f::Real, c::AbstractGray) = arith_colorant_type(c){multype(typeof(f),eltype(c))}(f*gray(c))
(*)(f::Real, c::TransparentGray) = arith_colorant_type(c){multype(typeof(f),eltype(c))}(f*gray(c), f*alpha(c))
(*)(c::AbstractGray, f::Real) = (*)(f, c)
(*)(c::TransparentGray, f::Real) = (*)(f, c)
(/)(c::AbstractGray, f::Real) = (one(f)/f)*c
(/)(n::Number, c::AbstractGray) = n/gray(c)
(/)(c::TransparentGray, f::Real) = (one(f)/f)*c
(/)(c::AbstractGray, f::Integer) = (one(eltype(c))/f)*c
(/)(c::TransparentGray, f::Integer) = (one(eltype(c))/f)*c
(+)(a::AbstractGray{S}, b::AbstractGray{T}) where {S,T} = color_rettype(a,b){sumtype(S,T)}(gray(a)+gray(b))
(+)(a::TransparentGray, b::TransparentGray) = color_rettype(a,b){sumtype(eltype(a),eltype(b))}(gray(a)+gray(b),alpha(a)+alpha(b))
(-)(a::AbstractGray{S}, b::AbstractGray{T}) where {S,T} = color_rettype(a,b){sumtype(S,T)}(gray(a)-gray(b))
(-)(a::TransparentGray, b::TransparentGray) = color_rettype(a,b){sumtype(eltype(a),eltype(b))}(gray(a)-gray(b),alpha(a)-alpha(b))
(*)(a::AbstractGray{S}, b::AbstractGray{T}) where {S,T} = color_rettype(a,b){multype(S,T)}(gray(a)*gray(b))
(^)(a::AbstractGray{S}, b::Integer) where {S} = arith_colorant_type(a){powtype(S,Int)}(gray(a)^convert(Int,b))
(^)(a::AbstractGray{S}, b::Real) where {S} = arith_colorant_type(a){powtype(S,typeof(b))}(gray(a)^b)
(+)(c::AbstractGray) = c
(+)(c::TransparentGray) = c
(-)(c::AbstractGray) = typeof(c)(-gray(c))
(-)(c::TransparentGray) = typeof(c)(-gray(c),-alpha(c))
(/)(a::AbstractGray, b::AbstractGray) = gray(a)/gray(b)
div(a::AbstractGray, b::AbstractGray) = div(gray(a), gray(b))
(+)(a::AbstractGray, b::Number) = gray(a)+b
(-)(a::AbstractGray, b::Number) = gray(a)-b
(+)(a::Number, b::AbstractGray) = a+gray(b)
(-)(a::Number, b::AbstractGray) = a-gray(b)
max(a::T, b::T) where {T<:AbstractGray} = T(max(gray(a),gray(b)))
max(a::AbstractGray, b::AbstractGray) = max(promote(a,b)...)
max(a::Number, b::AbstractGray) = max(promote(a,b)...)
max(a::AbstractGray, b::Number) = max(promote(a,b)...)
min(a::T, b::T) where {T<:AbstractGray} = T(min(gray(a),gray(b)))
min(a::AbstractGray, b::AbstractGray) = min(promote(a,b)...)
min(a::Number, b::AbstractGray) = min(promote(a,b)...)
min(a::AbstractGray, b::Number) = min(promote(a,b)...)

norm(c::AbstractGray) = abs(gray(c))
abs(c::TransparentGray) = abs(gray(c))+abs(alpha(c)) # should this have a different name?
abs(c::TransparentGrayNormed) = Float32(gray(c)) + Float32(alpha(c)) # should this have a different name?
abs2(c::AbstractGray) = gray(c)^2
abs2(c::AbstractGray{T}) where {T<:Normed} = Float32(gray(c))^2
abs2(c::TransparentGray) = gray(c)^2+alpha(c)^2
abs2(c::TransparentGrayNormed) = Float32(gray(c))^2 + Float32(alpha(c))^2
atan2(x::Gray, y::Gray) = atan2(convert(Real, x), convert(Real, y))
hypot(x::Gray, y::Gray) = hypot(convert(Real, x), convert(Real, y))
norm(c::TransparentGray) = sqrt(abs2(c))

(<)(g1::AbstractGray, g2::AbstractGray) = gray(g1) < gray(g2)
(<)(c::AbstractGray, r::Real) = gray(c) < r
(<)(r::Real, c::AbstractGray) = r < gray(c)
isless(g1::AbstractGray, g2::AbstractGray) = isless(gray(g1), gray(g2))
isless(c::AbstractGray, r::Real) = isless(gray(c), r)
isless(r::Real, c::AbstractGray) = isless(r, gray(c))
Base.isapprox(x::AbstractGray, y::AbstractGray; kwargs...) = isapprox(gray(x), gray(y); kwargs...)
Base.isapprox(x::TransparentGray, y::TransparentGray; kwargs...) = isapprox(gray(x), gray(y); kwargs...) && isapprox(alpha(x), alpha(y); kwargs...)
Base.isapprox(x::AbstractRGB, y::AbstractRGB; kwargs...) = isapprox(red(x), red(y); kwargs...) && isapprox(green(x), green(y); kwargs...) && isapprox(blue(x), blue(y); kwargs...)
Base.isapprox(x::TransparentRGB, y::TransparentRGB; kwargs...) = isapprox(alpha(x), alpha(y); kwargs...) && isapprox(red(x), red(y); kwargs...) && isapprox(green(x), green(y); kwargs...) && isapprox(blue(x), blue(y); kwargs...)

function Base.isapprox(x::AbstractArray{Cx},
                       y::AbstractArray{Cy};
                       rtol::Real=Base.rtoldefault(eltype(Cx),eltype(Cy)),
                       atol::Real=0,
                       norm::Function=vecnorm) where {Cx<:MathTypes,Cy<:MathTypes}
    d = norm(x - y)
    if isfinite(d)
        return d <= atol + rtol*max(norm(x), norm(y))
    else
        # Fall back to a component-wise approximate comparison
        return all(ab -> isapprox(ab[1], ab[2]; rtol=rtol, atol=atol), zip(x, y))
    end
end

zero(::Type{C}) where {C<:TransparentGray} = C(0,0)
oneunit(::Type{C}) where {C<:TransparentGray} = C(1,1)

dotc(x::T, y::T) where {T<:AbstractGray} = acc(gray(x))*acc(gray(y))
dotc(x::AbstractGray, y::AbstractGray) = dotc(promote(x, y)...)

float(::Type{T}) where {T<:Gray} = typeof(float(zero(T)))

# Mixed types
(+)(a::MathTypes, b::MathTypes) = (+)(Base.promote_noncircular(a, b)...)
(-)(a::MathTypes, b::MathTypes) = (-)(Base.promote_noncircular(a, b)...)

Compat.@dep_vectorize_2arg Gray max
Compat.@dep_vectorize_2arg Gray min

# Arrays
+(A::AbstractArray{C}) where {C<:MathTypes} = A

(+)(A::AbstractArray{CV}, b::AbstractRGB) where {CV<:AbstractRGB} = (.+)(A, b)
(+)(b::AbstractRGB, A::AbstractArray{CV}) where {CV<:AbstractRGB} = (.+)(b, A)
(-)(A::AbstractArray{CV}, b::AbstractRGB) where {CV<:AbstractRGB} = (.-)(A, b)
(-)(b::AbstractRGB, A::AbstractArray{CV}) where {CV<:AbstractRGB} = (.-)(b, A)
(*)(A::AbstractArray{T}, b::AbstractRGB) where {T<:Number} = A.*b
(*)(b::AbstractRGB, A::AbstractArray{T}) where {T<:Number} = A.*b

(+)(A::AbstractArray{CV}, b::TransparentRGB) where {CV<:TransparentRGB} = (.+)(A, b)
(+)(b::TransparentRGB, A::AbstractArray{CV}) where {CV<:TransparentRGB} = (.+)(b, A)
(-)(A::AbstractArray{CV}, b::TransparentRGB) where {CV<:TransparentRGB} = (.-)(A, b)
(-)(b::TransparentRGB, A::AbstractArray{CV}) where {CV<:TransparentRGB} = (.-)(b, A)
(*)(A::AbstractArray{T}, b::TransparentRGB) where {T<:Number} = A.*b
(*)(b::TransparentRGB, A::AbstractArray{T}) where {T<:Number} = A.*b

(+)(A::AbstractArray{CV}, b::AbstractGray) where {CV<:AbstractGray} = (.+)(A, b)
(+)(b::AbstractGray, A::AbstractArray{CV}) where {CV<:AbstractGray} = (.+)(b, A)
(-)(A::AbstractArray{CV}, b::AbstractGray) where {CV<:AbstractGray} = (.-)(A, b)
(-)(b::AbstractGray, A::AbstractArray{CV}) where {CV<:AbstractGray} = (.-)(b, A)
(*)(A::AbstractArray{T}, b::AbstractGray) where {T<:Number} = A.*b
(*)(b::AbstractGray, A::AbstractArray{T}) where {T<:Number} = A.*b
(/)(A::AbstractArray{C}, b::AbstractGray) where {C<:AbstractGray} = A./b

(+)(A::AbstractArray{CV}, b::TransparentGray) where {CV<:TransparentGray} = (.+)(A, b)
(+)(b::TransparentGray, A::AbstractArray{CV}) where {CV<:TransparentGray} = (.+)(b, A)
(-)(A::AbstractArray{CV}, b::TransparentGray) where {CV<:TransparentGray} = (.-)(A, b)
(-)(b::TransparentGray, A::AbstractArray{CV}) where {CV<:TransparentGray} = (.-)(b, A)
(*)(A::AbstractArray{T}, b::TransparentGray) where {T<:Number} = A.*b
(*)(b::TransparentGray, A::AbstractArray{T}) where {T<:Number} = A.*b

varm(v::AbstractArray{C}, s::AbstractGray; corrected::Bool=true) where {C<:AbstractGray} =
        varm(map(gray,v),gray(s); corrected=corrected)
real(::Type{C}) where {C<:AbstractGray} = real(eltype(C))

#histrange for Gray type
histrange(v::AbstractArray{Gray{T}}, n::Integer) where {T} = histrange(convert(Array{Float32}, map(gray, v)), n, :right)

# To help type inference
promote_array_type(F, ::Type{T}, ::Type{C}) where {T<:Real,C<:MathTypes} = base_colorant_type(C){Base.promote_array_type(F, T, eltype(C))}
promote_rule(::Type{T}, ::Type{C}) where {T<:Real,C<:AbstractGray} = promote_type(T, eltype(C))

typemin(::Type{T}) where {T<:ColorTypes.AbstractGray} = T(typemin(eltype(T)))
typemax(::Type{T}) where {T<:ColorTypes.AbstractGray} = T(typemax(eltype(T)))

typemin(::T) where {T<:ColorTypes.AbstractGray} = T(typemin(eltype(T)))
typemax(::T) where {T<:ColorTypes.AbstractGray} = T(typemax(eltype(T)))

# deprecations
function Base.one(::Type{C}) where {C<:Union{TransparentGray,AbstractRGB,TransparentRGB}}
    Base.depwarn("one($C) will soon switch to returning 1; you might need to switch to `oneunit`", :one)
    C(_onetuple(C)...)
end
_onetuple(::Type{C}) where {C<:Colorant{T,N}} where {T,N} = ntuple(d->1, Val(N))

for f in (:min, :max)
    @eval begin
        @deprecate($f{T<:Gray}(x::Number, y::AbstractArray{T}), $f.(x, y))
        @deprecate($f{T<:Gray}(x::AbstractArray{T}, y::Number), $f.(x, y))
    end
end

end
