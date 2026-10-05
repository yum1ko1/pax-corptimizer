extends RefCounted
## The political map's fields under their game 0.24 names. 0.24 renamed most of them to English and kept Russian
## aliases only for a few (вп, вид_карты, мат, отряды_карты, подписи, слой, слои, фон, выбранные…): asked by the old
## name, map.get() returned null and the tuning silently did nothing. key() gives the name the running game has —
## the 0.24 one when the object has it, else the old one (older games).

const MAP := {
	"_часы_слоёв": "_layers_clock",
	"холст": "canvas",
	"слой_линий": "lines_layer",
	"слой_значков": "icons_layer",
	"показ_фигурок": "figures_display",
	"базы_карты": "map_bases",
	"_кадр_стопок": "_stacks_frame",
	"_кэш_стопок": "_stacks_cache",
	"_галки": "_toggles",
	"бои_карты": "map_battles",
	"караваны_карты": "map_caravans",
	"показатели_карты": "map_indicators",
	"фронт_карты": "map_front",
	"связи_карты": "map_links",
	"пути_карты": "map_routes",
	"авиарейсы_карты": "map_flights",
	"промыслы_карты": "map_mines",
	"постройки_карты": "map_buildings",
}


static func key(obj: Object, old: String) -> String:
	var now := str(MAP.get(old, ""))
	if not now.is_empty() and obj != null and now in obj:
		return now
	return old


static func get_of(obj: Object, old: String) -> Variant:
	return obj.get(key(obj, old)) if obj != null else null


static func set_of(obj: Object, old: String, v: Variant) -> void:
	if obj != null:
		obj.set(key(obj, old), v)
