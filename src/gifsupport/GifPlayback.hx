package gifsupport;

class GifPlayback
{
	public var gif(default, null):Gif;
	public var frame(default, null):Int = 0;
	public var playing(default, null):Bool = false;
	public var finished(default, null):Bool = false;
	public var completedLoops(default, null):Int = 0;
	public var speed:Float = 1;
	public var onComplete:Void->Void;
	public var onLoop:Void->Void;

	var time:Float = 0;

	public function new(gif:Gif)
	{
		this.gif = gif;
	}

	public function play(restart:Bool = false):Void
	{
		if (restart || finished)
			reset();
		playing = true;
	}

	public function pause():Void
	{
		playing = false;
	}

	public function stop():Void
	{
		playing = false;
		reset();
	}

	public function goto(index:Int):Void
	{
		if (gif.frames.length == 0)
			return;
		frame = index < 0 ? 0 : (index >= gif.frames.length ? gif.frames.length - 1 : index);
		time = 0;
	}

	public function update(elapsed:Float):Bool
	{
		if (!playing || finished || gif.frames.length < 2)
			return false;

		time += elapsed * speed;
		var changed = false;

		while (playing)
		{
			var delay = gif.frames[frame].delay;
			if (delay < 10)
				delay = 10;
			if (time < delay)
				break;

			time -= delay;

			if (frame + 1 >= gif.frames.length)
			{
				completedLoops++;
				var plays = gif.playCount;
				if (plays > 0 && completedLoops >= plays)
				{
					finished = true;
					playing = false;
					time = 0;
					if (onComplete != null)
						onComplete();
					return changed;
				}
				frame = 0;
				if (onLoop != null)
					onLoop();
			}
			else
			{
				frame++;
			}

			changed = true;
		}

		return changed;
	}

	function reset():Void
	{
		frame = 0;
		time = 0;
		completedLoops = 0;
		finished = false;
	}
}
