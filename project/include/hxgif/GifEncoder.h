#pragma once

#include <cstdint>
#include <vector>

namespace hxgif
{
	class GifEncoder
	{
	public:
		GifEncoder(int width, int height, int loopCount);

		bool addFrame(const uint8_t* rgba, int delay);
		void finish();

		int getWidth() const;
		int getHeight() const;
		int getFrameCount() const;
		int getSize() const;
		bool copyOutput(uint8_t* destination) const;

	private:
		int width;
		int height;
		int loopCount;
		int frameCount;
		bool finished;
		std::vector<uint8_t> output;

		void writeByte(int value);
		void writeShort(int value);
		void writeHeader();
	};

	GifEncoder* createEncoder(int width, int height, int loopCount);
	void destroyEncoder(GifEncoder* encoder);
}
