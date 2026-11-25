package gifsupport.openfl;

#if (openfl && !flash)
import haxe.io.Bytes;
import lime.graphics.Image;
import lime.graphics.ImageBuffer;
import lime.graphics.PixelFormat;
import lime.utils.UInt8Array;
import openfl.Lib;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.PixelSnapping;
import openfl.events.Event;

class GifBitmap extends Bitmap
{
	public var gif(default, null):Gif;
	public var playback(default, null):GifPlayback;
	public var currentFrame(get, never):Int;
	public var playing(get, never):Bool;

	var frameBitmaps:Array<BitmapData>;
	var lastTime:Int = 0;

	public function new(gif:Gif, autoPlay:Bool = true, smoothing:Bool = false)
	{
		this.gif = gif;
		frameBitmaps = [for (i in 0...gif.frames.length) toBitmapData(gif, i)];
		playback = new GifPlayback(gif);
		playback.onComplete = dispatchComplete;

		super(frameBitmaps[0], PixelSnapping.AUTO, smoothing);

		addEventListener(Event.ENTER_FRAME, onEnterFrame);
		addEventListener(Event.REMOVED_FROM_STAGE, onRemoved);

		if (autoPlay)
			play();
	}

	public static function fromBytes(bytes:Bytes, autoPlay:Bool = true, smoothing:Bool = false):GifBitmap
	{
		return new GifBitmap(Gif.fromBytes(bytes), autoPlay, smoothing);
	}

	public static function fromAsset(id:String, autoPlay:Bool = true, smoothing:Bool = false):GifBitmap
	{
		return fromBytes(openfl.utils.Assets.getBytes(id), autoPlay, smoothing);
	}

	#if sys
	public static function fromFile(path:String, autoPlay:Bool = true, smoothing:Bool = false):GifBitmap
	{
		return new GifBitmap(Gif.fromFile(path), autoPlay, smoothing);
	}
	#end

	public static function toBitmapData(gif:Gif, index:Int):BitmapData
	{
		var pixels = gif.frames[index].pixels;
		var data = UInt8Array.fromBytes(pixels.sub(0, pixels.length));
		var buffer = new ImageBuffer(data, gif.width, gif.height, 32, PixelFormat.RGBA32);
		buffer.transparent = true;
		return BitmapData.fromImage(new Image(buffer), true);
	}

	public function play(restart:Bool = false):Void
	{
		lastTime = Lib.getTimer();
		playback.play(restart);
		showFrame(playback.frame);
	}

	public function pause():Void
	{
		playback.pause();
	}

	public function stop():Void
	{
		playback.stop();
		showFrame(0);
	}

	public function gotoFrame(index:Int):Void
	{
		playback.goto(index);
		showFrame(playback.frame);
	}

	public function dispose():Void
	{
		removeEventListener(Event.ENTER_FRAME, onEnterFrame);
		removeEventListener(Event.REMOVED_FROM_STAGE, onRemoved);
		bitmapData = null;
		if (frameBitmaps != null)
			for (bitmap in frameBitmaps)
				bitmap.dispose();
		frameBitmaps = null;
	}

	function showFrame(index:Int):Void
	{
		if (frameBitmaps == null)
			return;
		var smooth = smoothing;
		bitmapData = frameBitmaps[index];
		smoothing = smooth;
	}

	function onEnterFrame(_):Void
	{
		var now = Lib.getTimer();
		var elapsed = now - lastTime;
		lastTime = now;

		if (playback.update(elapsed))
			showFrame(playback.frame);
	}

	function onRemoved(_):Void
	{
		lastTime = Lib.getTimer();
	}

	function dispatchComplete():Void
	{
		dispatchEvent(new Event(Event.COMPLETE));
	}

	function get_currentFrame():Int
	{
		return playback.frame;
	}

	function get_playing():Bool
	{
		return playback.playing;
	}
}
#end
