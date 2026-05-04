extends Node

signal log_added(message: String)

func add_log(message: String):
	log_added.emit(message)
	print("[LOG] ", message)
