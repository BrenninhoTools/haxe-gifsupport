#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace hxgif
{
	struct DecodedFrame
	{
		std::vector<uint8_t> pixels;
		int delay;
		int left;
		int top;
		int width;
		int height;
		int disposal;
	};

	class GifDecoder
	{
	public:
		GifDecoder();

		bool decode(const uint8_t* data, int length);
		void clear();

		int getWidth() const;
		int getHeight() const;
		int getLoopCount() const;
		int getFrameCount() const;
		int getFrameDelay(int index) const;
		int getFrameDisposal(int index) const;
		bool copyFrame(int index, uint8_t* destination) const;
		const char* getError() const;

		static bool isGif(const uint8_t* data, int length);

	private:
		int width;
		int height;
		int loopCount;
		std::string error;
		std::vector<DecodedFrame> frames;
	};

	GifDecoder* createDecoder();
	void destroyDecoder(GifDecoder* decoder);
}
