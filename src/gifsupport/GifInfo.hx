package gifsupport;

class GifInfo
{
	public var version(default, null):String;
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var numFrames(default, null):Int;
	public var loopCount(default, null):Int;
	public var duration(default, null):Int;
	public var backgroundColor(default, null):Int;
	public var pixelAspectRatio(default, null):Float;
	public var comments(default, null):Array<String>;

	public var animated(get, never):Bool;
	public var playCount(get, never):Int;
	public var decodedSize(get, never):Float;

	public function new(version:String, width:Int, height:Int, numFrames:Int, loopCount:Int, duration:Int, backgroundColor:Int, pixelAspectRatio:Float,
			comments:Array<String>)
	{
		this.version = version;
		this.width = width;
		this.height = height;
		this.numFrames = numFrames;
		this.loopCount = loopCount;
		this.duration = duration;
		this.backgroundColor = backgroundColor;
		this.pixelAspectRatio = pixelAspectRatio;
		this.comments = comments;
	}

	function get_animated():Bool
	{
		return numFrames > 1;
	}

	function get_playCount():Int
	{
		if (loopCount < 0)
			return 1;
		if (loopCount == 0)
			return 0;
		return loopCount + 1;
	}

	function get_decodedSize():Float
	{
		return width * 1.0 * height * 4 * numFrames;
	}
}
