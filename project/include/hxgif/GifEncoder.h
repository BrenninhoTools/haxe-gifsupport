#pragma once

#include <cstdint>
#include <vector>

namespace hxgif
{
	class GifEncoder
	{
	public:
		GifEncoder(int width, int height, int loopCount, bool optimize, bool dither, int alphaThreshold);

		bool addComment(const uint8_t* text, int length);
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
		bool optimize;
		bool dither;
		int alphaThreshold;
		bool hasPending;
		int pendingDelay;
		std::vector<uint8_t> output;
		std::vector<uint8_t> canvas;
		std::vector<uint8_t> pending;

		void writeByte(int value);
		void writeShort(int value);
		void writeHeader();
		void normalize(const uint8_t* rgba, std::vector<uint8_t>& result) const;
		void flushPending(const std::vector<uint8_t>* next);
		void writeFrame(const std::vector<uint8_t>& frame, int delay, int disposal, int regionX, int regionY, int regionWidth, int regionHeight, const std::vector<uint8_t>* compare);
	};

	GifEncoder* createEncoder(int width, int height, int loopCount, bool optimize, bool dither, int alphaThreshold);
	void destroyEncoder(GifEncoder* encoder);
}
