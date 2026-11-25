package gifsupport.flixel;

#if flixel
import flixel.FlxSprite;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import gifsupport.openfl.GifBitmap;
import haxe.io.Bytes;

class FlxGifAtlas
{
	public static function framesFromGif(gif:Gif, prefix:String = "gif", columns:Int = 0, padding:Int = 1):FlxAtlasFrames
	{
		var sheet = gif.toSpriteSheet(columns, padding);
		var graphic = FlxGraphic.fromBitmapData(GifBitmap.spriteSheetToBitmapData(sheet), false, null, false);
		return FlxAtlasFrames.fromSparrow(graphic, sheet.toSparrowXml("gif.png", prefix));
	}

	public static function loadGif(sprite:FlxSprite, gif:Gif, animationName:String = "gif", ?frameRate:Float, ?looped:Bool, autoPlay:Bool = true):FlxSprite
	{
		sprite.frames = framesFromGif(gif, animationName);
		var fps = frameRate == null ? gif.averageFrameRate : frameRate;
		sprite.animation.addByPrefix(animationName, animationName, fps <= 0 ? 10 : fps, looped == null ? gif.playCount != 1 : looped);
		if (autoPlay)
			sprite.animation.play(animationName);
		return sprite;
	}

	public static function loadGifBytes(sprite:FlxSprite, bytes:Bytes, animationName:String = "gif", ?frameRate:Float, ?looped:Bool,
			autoPlay:Bool = true):FlxSprite
	{
		return loadGif(sprite, Gif.fromBytes(bytes), animationName, frameRate, looped, autoPlay);
	}

	public static function loadGifAsset(sprite:FlxSprite, id:String, animationName:String = "gif", ?frameRate:Float, ?looped:Bool,
			autoPlay:Bool = true):FlxSprite
	{
		return loadGifBytes(sprite, openfl.utils.Assets.getBytes(id), animationName, frameRate, looped, autoPlay);
	}
}
#end
