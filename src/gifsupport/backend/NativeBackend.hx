package gifsupport.backend;

#if cpp
import cpp.NativeArray;
import gifsupport.native.NativeGifDecoder;
import gifsupport.native.NativeGifEncoder;
import haxe.io.Bytes;

class NativeBackend
{
	public static function decode(bytes:Bytes):Gif
	{
		var decoder = NativeGifDecoder.create();

		try
		{
			if (!decoder.decode(NativeArray.address(bytes.getData(), 0).constRaw, bytes.length))
				throw new GifException(decoder.getError().toString());

			var width = decoder.getWidth();
			var height = decoder.getHeight();
			var size = width * height * 4;
			var frames = new Array<GifFrame>();

			for (i in 0...decoder.getFrameCount())
			{
				var pixels = Bytes.alloc(size);
				decoder.copyFrame(i, NativeArray.address(pixels.getData(), 0).raw);
				frames.push(new GifFrame(pixels, decoder.getFrameDelay(i), decoder.getFrameDisposal(i)));
			}

			var gif = new Gif(width, height, decoder.getLoopCount(), frames);
			NativeGifDecoder.destroy(decoder);
			return gif;
		}
		catch (error:haxe.Exception)
		{
			NativeGifDecoder.destroy(decoder);
			throw error;
		}
	}
}

@:headerInclude("hxgif/GifEncoder.h")
class NativeEncoderHandle extends cpp.Finalizable
{
	var encoder:cpp.Star<NativeGifEncoder>;

	public function new(width:Int, height:Int, loopCount:Int)
	{
		super();
		encoder = NativeGifEncoder.create(width, height, loopCount);
	}

	public function addFrame(pixels:Bytes, delay:Int):Void
	{
		if (!encoder.addFrame(NativeArray.address(pixels.getData(), 0).constRaw, delay))
			throw new GifException("Failed to encode frame");
	}

	public function finish():Bytes
	{
		encoder.finish();
		var result = Bytes.alloc(encoder.getSize());
		encoder.copyOutput(NativeArray.address(result.getData(), 0).raw);
		release();
		return result;
	}

	public function release():Void
	{
		if (encoder != null)
		{
			NativeGifEncoder.destroy(encoder);
			encoder = null;
		}
	}

	override public function finalize():Void
	{
		release();
	}
}
#end
