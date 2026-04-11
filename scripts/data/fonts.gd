class_name Fonts
extends RefCounted
## 全局像素字体预加载。所有“动态”加载 UI 脚本统一从此处引用，避免重复 preload。
## font_size 必须设为字体 px 的整数倍。

const PIXEL_8: Font = preload("res://assets/font/fusion-pixel-8px-proportional-zh_hans.otf")
const PIXEL_10: Font = preload("res://assets/font/fusion-pixel-10px-proportional-zh_hans.otf")
const PIXEL_12: Font = preload("res://assets/font/fusion-pixel-12px-proportional-zh_hans.otf")
const PIXEL_16: Font = preload("res://assets/font/unifont-15.1.04.otf")
