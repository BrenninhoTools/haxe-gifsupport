#pragma once

namespace hxgif
{
	class GifEncoderImpl;

	class GifEncoder
	{
	public:
		GifEncoder(int width, int height, int loopCount, bool optimize, bool dither, int alphaThreshold);
		~GifEncoder();

		bool addComment(const unsigned char* text, int length);
		bool addFrame(const unsigned char* rgba, int delay);
		void finish();

		int getWidth() const;
		int getHeight() const;
		int getFrameCount() const;
		int getSize() const;
		bool copyOutput(unsigned char* destination) const;

	private:
		GifEncoder(const GifEncoder&);
		GifEncoder& operator=(const GifEncoder&);

		GifEncoderImpl* impl;
	};

	GifEncoder* createEncoder(int width, int height, int loopCount, bool optimize, bool dither, int alphaThreshold);
	void destroyEncoder(GifEncoder* encoder);
}
