package gifsupport.native;

#if cpp
@:buildXml('<include name="${haxelib:haxe-gifsupport}/project/Build.xml" />')
@:include("hxgif/GifEncoder.h")
@:native("hxgif::GifEncoder")
@:structAccess
extern class NativeGifEncoder
{
	@:native("hxgif::createEncoder")
	static function create(width:Int, height:Int, loopCount:Int):cpp.Star<NativeGifEncoder>;

	@:native("hxgif::destroyEncoder")
	static function destroy(encoder:cpp.Star<NativeGifEncoder>):Void;

	function addFrame(rgba:cpp.RawConstPointer<cpp.UInt8>, delay:Int):Bool;
	function finish():Void;
	function getWidth():Int;
	function getHeight():Int;
	function getFrameCount():Int;
	function getSize():Int;
	function copyOutput(destination:cpp.RawPointer<cpp.UInt8>):Bool;
}
#end
