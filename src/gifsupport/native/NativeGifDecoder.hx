package gifsupport.native;

#if cpp
@:buildXml('<include name="${haxelib:haxe-gifsupport}/project/Build.xml" />')
@:include("hxgif/GifDecoder.h")
@:native("hxgif::GifDecoder")
@:structAccess
extern class NativeGifDecoder
{
	@:native("hxgif::createDecoder")
	static function create():cpp.Star<NativeGifDecoder>;

	@:native("hxgif::destroyDecoder")
	static function destroy(decoder:cpp.Star<NativeGifDecoder>):Void;

	@:native("hxgif::GifDecoder::isGif")
	static function isGif(data:cpp.RawConstPointer<cpp.UInt8>, length:Int):Bool;

	function decode(data:cpp.RawConstPointer<cpp.UInt8>, length:Int):Bool;
	function clear():Void;
	function getWidth():Int;
	function getHeight():Int;
	function getLoopCount():Int;
	function getFrameCount():Int;
	function getFrameDelay(index:Int):Int;
	function getFrameDisposal(index:Int):Int;
	function copyFrame(index:Int, destination:cpp.RawPointer<cpp.UInt8>):Bool;
	function getError():cpp.ConstCharStar;
}
#end
