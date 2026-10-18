# stringtype=InlineString (or a fixed String1..String255) for CSV.File/read.
#
# InlineStrings are fixed-width isbits strings (1, 3, 7, 15, 31, 63, 127, 255
# byte payloads). `stringtype=InlineString` picks the smallest width that fits
# each column's longest value, up to String31, then falls back to String; a
# specific `String15` etc. fixes the width, erroring on an over-long value like
# `String15("...")` would.
#
# Conversion runs from the DataString payloads directly: inline values
# rebuild from the payload words, views copy out of the retained buffer — one
# pass, no intermediate Vector{String}.
#
# forks: the extension is a set of conformances. `Vector{S}`, for an InlineString
# type `S` (with or without `Missing`, and the auto-width `InlineString` itself),
# conforms to CSV's trait `ColumnParsers.TextColumn`, whose operations the
# reader calls for any string type it does not know. Declaring a conformance
# adds a method to the conformance registry and no method to CSV's internal
# functions, so loading InlineStrings invalidates none of the reader's compiled
# code. Upstream's extension added methods to `_stringsink`,
# `_settledstringtype`, `_materializecolumn`, `_rowstringtype`, `_lazyeltype`,
# `_rowstring` and `_levelvector`.
module CSVInlineStringsExt

using CSV, InlineStrings
using TraitWorld: @implement
using CSV.ColumnParsers: TextColumn

const _WIDTHS = (String1, String3, String7, String15, String31, String63, String127, String255)

_capacity(::Type{T}) where {T <: InlineString} = sizeof(T) - 1

# smallest InlineString type holding `n` bytes
function _fitwidth(n::Int)
    for T in _WIDTHS
        n <= _capacity(T) && return T
    end
    throw(ArgumentError("value of $n bytes exceeds the InlineString maximum of 255"))
end

@inline function _inl(::Type{T}, s::CSV.DataString) where {T <: InlineString}
    n = ncodeunits(s)
    n > _capacity(T) &&
        throw(ArgumentError("value of $n bytes does not fit $T"))
    if n > CSV.INLINE_MAX
        GC.@preserve s begin
            return T(pointer(s.data, CSV.payloadpos(s.p)), n)
        end
    end
    # inline payload: build through a stack scratch (≤12 bytes)
    buf = Ref{NTuple{16, UInt8}}()
    p = Ptr{UInt8}(Base.unsafe_convert(Ptr{NTuple{16, UInt8}}, buf))
    GC.@preserve buf begin
        @inbounds for i in 1:n
            unsafe_store!(p, codeunit(s, i), i)
        end
        return T(p, n)
    end
end

# `stringtype=InlineString` stops at String31: wider inline strings copy
# 64–256 bytes per cell. This policy limits the cost of copying wide cells.
# A column whose longest value exceeds it comes back as `String`, so a valid
# file never fails to read because of its text width.
const _AUTO_MAX_WIDTH = _capacity(String31)

# the cell type text of `maxlen` bytes settles to: a fixed width stays; the
# auto width is the smallest that fits, or `String` past the ceiling
_settled(::Type{InlineString}, maxlen::Int) = maxlen <= _AUTO_MAX_WIDTH ? _fitwidth(maxlen) : String
_settled(::Type{T}, maxlen::Int) where {T <: InlineString} = T

_newcolumn(::Type{S}, n::Int, withmissing::Bool) where {S} =
    withmissing ? Vector{Union{S, Missing}}(undef, n) : Vector{S}(undef, n)

# per-cell conversion for row access: the auto width picks the smallest width per cell
_rowcell(::Type{InlineString}, x::CSV.DataString) =
    (ncodeunits(x) <= _AUTO_MAX_WIDTH ? _inl(_fitwidth(ncodeunits(x)), x) : String(x))::Union{InlineString, String}
_rowcell(::Type{T}, x::CSV.DataString) where {T <: InlineString} = _inl(T, x)

# Auto width can return either an InlineString or an owned String. Tables
# consumers must allocate a column that can hold both, including >255 bytes.
_rowtype(::Type{InlineString}) = Union{InlineString, String}
_rowtype(::Type{T}) where {T <: InlineString} = T

# the conformances: `Vector{S}` and `Vector{Union{S, Missing}}` for each InlineString type `S`
# and for the auto width `InlineString`
for S in (_WIDTHS..., InlineString), V in (Vector{S}, Vector{Union{S, Missing}})
    @eval @implement TextColumn $V begin
        textcolumn(c, maxlen, n, withmissing) = _newcolumn(_settled($S, maxlen), n, withmissing)
        settext!(c, i, x) = (@inbounds c[i] = x === missing ? missing : _inl($S, x); nothing)
        rowtexttype(c) = _rowtype($S)
        rowtext(c, x) = _rowcell($S, x)
    end
end

end # module
