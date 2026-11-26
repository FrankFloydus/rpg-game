@tool
extends PopupPanel

const Style := preload("res://addons/hearth_workbench/workbench_style.gd")
const RESULT_LIMIT := 32

@onready var _query: LineEdit = %Query
@onready var _results: Tree = %Results
var _entries: Array[Dictionary] = []
var _previous_focus: WeakRef
var _scale := 1.0
var _maximum_height := 0
var _content_height := 0


func configure(scale: float) -> void:
	_scale = scale
	Style.inset(%Inset, roundi(14 * scale), roundi(12 * scale))
	%Context.add_theme_color_override("font_color", Style.MUTED)
	%Hint.add_theme_color_override("font_color", Style.MUTED)
	_results.set_column_expand_ratio(0, 3)
	_results.set_column_expand_ratio(1, 2)
	_query.text_changed.connect(_filter)
	_query.gui_input.connect(_query_key)
	_results.item_activated.connect(_activate)
	popup_hide.connect(_restore_focus)


func open(context: String, entries: Array[Dictionary], dimensions: Vector2i, current_focus: Control) -> void:
	_entries = entries
	_previous_focus = weakref(current_focus) if current_focus != null else null
	_maximum_height = dimensions.y
	%Context.text = context
	_query.text = ""
	_filter("")
	popup_centered(dimensions)
	size.y = _content_height
	_query.grab_focus()


func _filter(query: String) -> void:
	var terms := query.to_lower().replace("_", " ").split(" ", false)
	var matches: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		if terms.is_empty():
			if entry.group == "Actions" or entry.get("nearby", false):
				matches.append({"entry": entry, "score": 0})
			continue
		var title := str(entry.label).to_lower()
		var keywords := str(entry.get("keywords", "")).to_lower().replace("_", " ")
		var score := _score(terms, title, keywords)
		if score >= 0:
			var current := bool(entry.get("nearby", false)) or bool(entry.get("focused", false))
			matches.append({"entry": entry, "score": score + (2 if current else 0)})
	matches.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	_results.clear()
	var root := _results.create_item()
	var groups := {}
	var first: TreeItem
	for index in mini(RESULT_LIMIT, matches.size()):
		var entry: Dictionary = matches[index].entry
		var header: TreeItem = groups.get(entry.group)
		if header == null:
			header = _results.create_item(root)
			header.set_text(0, entry.group)
			header.set_selectable(0, false)
			header.set_selectable(1, false)
			header.set_custom_color(0, Style.MUTED)
			groups[entry.group] = header
		var item := _results.create_item(header)
		item.set_text(0, entry.label)
		item.set_tooltip_text(0, entry.label)
		item.set_metadata(0, entry.action)
		item.set_text(1, entry.get("detail", ""))
		item.set_tooltip_text(1, entry.get("detail", ""))
		item.set_custom_color(1, Style.MUTED)
		item.set_selectable(1, false)
		if first == null:
			first = item
	if first != null:
		first.select(0)
	else:
		var empty := _results.create_item(root)
		empty.set_text(0, "No results. Try a shorter name or ID.")
		empty.set_selectable(0, false)
		empty.set_selectable(1, false)
	var rows := maxi(1, mini(RESULT_LIMIT, matches.size()) + groups.size())
	_content_height = mini(_maximum_height, roundi((124 + rows * 26) * _scale))
	if visible:
		size.y = _content_height


func _score(terms: PackedStringArray, title: String, keywords: String) -> int:
	var score := 0
	for term: String in terms:
		if title.begins_with(term):
			score += 12
		elif term in title:
			score += 8
		elif term in keywords:
			score += 2
		else:
			return -1
	if title == " ".join(terms):
		score += 25
	return score


func _query_key(event: InputEvent) -> void:
	if event is not InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_UP, KEY_DOWN:
			var current := _results.get_selected()
			if current != null:
				var next := current.get_prev_visible() if event.keycode == KEY_UP else current.get_next_visible()
				while next != null and not next.is_selectable(0):
					next = next.get_prev_visible() if event.keycode == KEY_UP else next.get_next_visible()
				if next != null:
					next.select(0)
					_results.scroll_to_item(next)
		KEY_ENTER, KEY_KP_ENTER:
			_activate()
		KEY_ESCAPE:
			hide()
		_:
			return
	_query.accept_event()


func _activate() -> void:
	var selected := _results.get_selected()
	if selected == null:
		return
	var action: Callable = selected.get_metadata(0)
	hide()
	action.call_deferred()


func _restore_focus() -> void:
	if _previous_focus == null:
		return
	var target := _previous_focus
	_previous_focus = null
	_focus_previous.call_deferred(target)


func _focus_previous(target: WeakRef) -> void:
	var focus := target.get_ref() as Control
	if is_instance_valid(focus) and focus.is_inside_tree() and focus.is_visible_in_tree():
		focus.grab_focus()
