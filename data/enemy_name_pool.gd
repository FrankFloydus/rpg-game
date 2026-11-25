@tool
extends Resource
## Original word pieces available to rare enemies in the selected families.

## Exact family identifiers used by enemy definitions. An empty list makes this a fallback pool.
@export var families: PackedStringArray
## Leading words for the rare enemy's compound name.
@export var beginnings: PackedStringArray
## Lowercase endings appended directly to the leading word.
@export var endings: PackedStringArray
## Optional titles appended after the compound name, with a space inserted automatically.
@export var titles: PackedStringArray
