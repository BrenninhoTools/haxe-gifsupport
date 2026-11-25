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
		bool interlaced;
	};

	class GifDecoder
	{
	public:
		GifDecoder();

		bool decode(const uint8_t* data, int length, int maxFrames);
		void clear();

		int getWidth() const;
		int getHeight() const;
		int getLoopCount() const;
		int getVersion() const;
		int getBackgroundColor() const;
		int getAspectRatio() const;
		int getCommentCount() const;
		int getCommentLength(int index) const;
		bool copyComment(int index, uint8_t* destination) const;
		int getFrameCount() const;
		int getFrameDelay(int index) const;
		int getFrameDisposal(int index) const;
		int getFrameLeft(int index) const;
		int getFrameTop(int index) const;
		int getFrameWidth(int index) const;
		int getFrameHeight(int index) const;
		bool getFrameInterlaced(int index) const;
		bool copyFrame(int index, uint8_t* destination) const;
		const char* getError() const;

		static bool isGif(const uint8_t* data, int length);

	private:
		int width;
		int height;
		int loopCount;
		int version;
		int backgroundColor;
		int aspectRatio;
		std::string error;
		std::vector<std::string> comments;
		std::vector<DecodedFrame> frames;
	};

	GifDecoder* createDecoder();
	void destroyDecoder(GifDecoder* decoder);
}
