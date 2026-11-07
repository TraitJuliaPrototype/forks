# PooledArrays' vectors have a reference pool: `PooledColumn`, by the trait's owner (Tables) in its
# extension with PooledArrays as the trigger (traits reference §10.1).
module TablesPooledArraysExt
using Tables, PooledArrays, TraitWorld
using Tables: ColumnCore
using Tables.ColumnCore: PooledColumn, _pool_nlevels, _pool_levelcode, _pool_level
# the operations' methods first (Tables owns their functions), then the family by them (traits reference §4.7)
ColumnCore.nlevels(c::PooledVector) = _pool_nlevels(c)
ColumnCore.levelcode(c::PooledVector, i::Int) = _pool_levelcode(c, i)
ColumnCore.level(c::PooledVector, k::Int) = _pool_level(c, k)
@implement PooledColumn{T} PooledArray{T, R, 1, RA} where {T, R, RA}
end
