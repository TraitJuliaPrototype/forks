# CategoricalArrays' vectors have a reference pool: `PooledColumn`, by the trait's owner (Tables) in its
# extension with CategoricalArrays as the trigger (traits reference §10.1).
module TablesCategoricalArraysExt
using Tables, CategoricalArrays, TraitWorld
using Tables: ColumnCore
using Tables.ColumnCore: PooledColumn, _pool_nlevels, _pool_levelcode, _pool_level
# the operations' methods first (Tables owns their functions), then the family by them (traits reference §4.7)
ColumnCore.nlevels(c::CategoricalVector) = _pool_nlevels(c)
ColumnCore.levelcode(c::CategoricalVector, i::Int) = _pool_levelcode(c, i)
ColumnCore.level(c::CategoricalVector, k::Int) = _pool_level(c, k)
@implement PooledColumn{T} CategoricalArray{T, 1, R, V, C, U} where {T, R, V, C, U}
end
