#include "hxgif/GifDecoder.h"

#include <algorithm>
#include <cstring>

namespace hxgif
{
	namespace
	{
		const long long maxCanvasPixels = 1LL << 26;

		struct RawFrame
		{
			int left;
			int top;
			int width;
			int height;
			bool interlaced;
			int delay;
			int disposal;
			int transparentIndex;
			int minCodeSize;
			std::vector<uint8_t> palette;
			std::vector<uint8_t> data;
		};

		int readShort(const uint8_t* data, int position)
		{
			return data[position] | (data[position + 1] << 8);
		}

		int skipSubBlocks(const uint8_t* data, int length, int position)
		{
			while (position < length)
			{
				int size = data[position];
				position += 1 + size;
				if (size == 0)
					return position;
			}
			return length;
		}

		int decompress(const RawFrame& frame, std::vector<uint8_t>& indices)
		{
			long long total = (long long)frame.width * (long long)frame.height;
			indices.assign((size_t)total, 0);

			int minCodeSize = frame.minCodeSize;
			if (minCodeSize < 1 || minCodeSize > 11 || total == 0)
				return 0;

			uint16_t prefix[4096];
			uint8_t suffix[4096];
			uint8_t first[4096];
			uint16_t lengths[4096];

			int clearCode = 1 << minCodeSize;
			int endCode = clearCode + 1;

			for (int i = 0; i < clearCode; i++)
			{
				prefix[i] = 0;
				suffix[i] = (uint8_t)i;
				first[i] = (uint8_t)i;
				lengths[i] = 1;
			}

			int codeSize = minCodeSize + 1;
			int nextCode = clearCode + 2;
			int previous = -1;

			const std::vector<uint8_t>& data = frame.data;
			size_t dataPosition = 0;
			uint32_t bitBuffer = 0;
			int bitCount = 0;
			long long output = 0;

			while (output < total)
			{
				while (bitCount < codeSize && dataPosition < data.size())
				{
					bitBuffer |= (uint32_t)data[dataPosition++] << bitCount;
					bitCount += 8;
				}

				if (bitCount < codeSize)
					break;

				int code = (int)(bitBuffer & ((1u << codeSize) - 1));
				bitBuffer >>= codeSize;
				bitCount -= codeSize;

				if (code == clearCode)
				{
					codeSize = minCodeSize + 1;
					nextCode = clearCode + 2;
					previous = -1;
					continue;
				}

				if (code == endCode)
					break;

				if (previous == -1)
				{
					if (code >= clearCode)
						break;

					indices[(size_t)output++] = (uint8_t)code;
					previous = code;
					continue;
				}

				if (code < nextCode)
				{
					if (nextCode < 4096)
					{
						prefix[nextCode] = (uint16_t)previous;
						suffix[nextCode] = first[code];
						first[nextCode] = first[previous];
						lengths[nextCode] = (uint16_t)(lengths[previous] + 1);
						nextCode++;
					}
				}
				else if (code == nextCode && nextCode < 4096)
				{
					prefix[nextCode] = (uint16_t)previous;
					suffix[nextCode] = first[previous];
					first[nextCode] = first[previous];
					lengths[nextCode] = (uint16_t)(lengths[previous] + 1);
					nextCode++;
				}
				else
				{
					break;
				}

				long long end = output + lengths[code];
				int current = code;
				for (long long position = end - 1; position >= output; position--)
				{
					if (position < total)
						indices[(size_t)position] = suffix[current];
					current = prefix[current];
				}
				output = end < total ? end : total;

				previous = code;

				if (nextCode == (1 << codeSize) && codeSize < 12)
					codeSize++;
			}

			return (int)output;
		}
	}

	GifDecoder::GifDecoder() : width(0), height(0), loopCount(-1), version(89), backgroundColor(-1), aspectRatio(0)
	{
	}

	void GifDecoder::clear()
	{
		width = 0;
		height = 0;
		loopCount = -1;
		version = 89;
		backgroundColor = -1;
		aspectRatio = 0;
		error.clear();
		comments.clear();
		frames.clear();
	}

	bool GifDecoder::isGif(const uint8_t* data, int length)
	{
		if (data == nullptr || length < 6)
			return false;

		return std::memcmp(data, "GIF87a", 6) == 0 || std::memcmp(data, "GIF89a", 6) == 0;
	}

	bool GifDecoder::decode(const uint8_t* data, int length, int maxFrames)
	{
		clear();

		if (!isGif(data, length) || length < 13)
		{
			error = "Invalid GIF header";
			return false;
		}

		int canvasWidth = readShort(data, 6);
		int canvasHeight = readShort(data, 8);
		int screenFlags = data[10];
		int backgroundIndex = data[11];
		aspectRatio = data[12];
		version = data[4] == '7' ? 87 : 89;
		int position = 13;

		std::vector<uint8_t> globalPalette;
		if (screenFlags & 0x80)
		{
			int size = 2 << (screenFlags & 7);
			if (position + size * 3 > length)
			{
				error = "Truncated global color table";
				return false;
			}
			globalPalette.assign(data + position, data + position + size * 3);
			position += size * 3;

			if (backgroundIndex < size)
			{
				const uint8_t* color = globalPalette.data() + backgroundIndex * 3;
				backgroundColor = (int)(0xFF000000u | ((uint32_t)color[0] << 16) | ((uint32_t)color[1] << 8) | (uint32_t)color[2]);
			}
		}

		int pendingDelay = 0;
		int pendingDisposal = 0;
		int pendingTransparent = -1;
		std::vector<RawFrame> rawFrames;

		while (position < length)
		{
			if (maxFrames > 0 && (int)rawFrames.size() >= maxFrames)
				break;

			int block = data[position++];

			if (block == 0x3B)
				break;

			if (block == 0x21)
			{
				if (position >= length)
					break;

				int label = data[position++];

				if (label == 0xF9 && position + 5 <= length && data[position] >= 4)
				{
					int flags = data[position + 1];
					pendingDisposal = (flags >> 2) & 7;
					pendingDelay = readShort(data, position + 2);
					pendingTransparent = (flags & 1) ? data[position + 4] : -1;
				}
				else if (label == 0xFF && position + 12 <= length && data[position] == 11)
				{
					const uint8_t* identifier = data + position + 1;
					if (std::memcmp(identifier, "NETSCAPE2.0", 11) == 0 || std::memcmp(identifier, "ANIMEXTS1.0", 11) == 0)
					{
						int sub = position + 12;
						if (sub + 4 <= length && data[sub] >= 3 && (data[sub + 1] & 7) == 1)
							loopCount = readShort(data, sub + 2);
					}
				}
				else if (label == 0xFE)
				{
					std::string text;
					int sub = position;
					while (sub < length)
					{
						int size = data[sub++];
						if (size == 0)
							break;
						int available = std::min(size, length - sub);
						text.append((const char*)(data + sub), (size_t)available);
						sub += available;
					}
					comments.push_back(std::move(text));
				}

				position = skipSubBlocks(data, length, position);
				continue;
			}

			if (block == 0x2C)
			{
				if (position + 9 > length)
					break;

				RawFrame frame;
				frame.left = readShort(data, position);
				frame.top = readShort(data, position + 2);
				frame.width = readShort(data, position + 4);
				frame.height = readShort(data, position + 6);
				int flags = data[position + 8];
				frame.interlaced = (flags & 0x40) != 0;
				position += 9;

				if (flags & 0x80)
				{
					int size = 2 << (flags & 7);
					if (position + size * 3 > length)
						break;
					frame.palette.assign(data + position, data + position + size * 3);
					position += size * 3;
				}
				else
				{
					frame.palette = globalPalette;
				}

				if (position >= length)
					break;

				frame.minCodeSize = data[position++];

				while (position < length)
				{
					int size = data[position++];
					if (size == 0)
						break;
					int available = std::min(size, length - position);
					frame.data.insert(frame.data.end(), data + position, data + position + available);
					position += available;
				}

				frame.delay = pendingDelay * 10;
				if (frame.delay <= 10)
					frame.delay = 100;
				frame.disposal = pendingDisposal;
				frame.transparentIndex = pendingTransparent;

				pendingDelay = 0;
				pendingDisposal = 0;
				pendingTransparent = -1;

				rawFrames.push_back(std::move(frame));
				continue;
			}

			break;
		}

		if (rawFrames.empty())
		{
			error = "GIF contains no frames";
			return false;
		}

		if (canvasWidth == 0 || canvasHeight == 0)
		{
			for (const RawFrame& frame : rawFrames)
			{
				canvasWidth = std::max(canvasWidth, frame.left + frame.width);
				canvasHeight = std::max(canvasHeight, frame.top + frame.height);
			}
		}

		long long canvasPixels = (long long)canvasWidth * (long long)canvasHeight;
		if (canvasPixels <= 0 || canvasPixels > maxCanvasPixels)
		{
			error = "Invalid GIF dimensions";
			return false;
		}

		width = canvasWidth;
		height = canvasHeight;

		size_t canvasBytes = (size_t)canvasPixels * 4;
		std::vector<uint8_t> canvas(canvasBytes, 0);
		std::vector<uint8_t> saved;
		std::vector<uint8_t> indices;
		std::vector<int> rowMap;

		frames.reserve(rawFrames.size());

		for (const RawFrame& raw : rawFrames)
		{
			long long framePixels = (long long)raw.width * (long long)raw.height;

			if (raw.disposal == 3)
				saved = canvas;

			if (framePixels > 0 && framePixels <= maxCanvasPixels)
			{
				int decoded = decompress(raw, indices);

				rowMap.resize(raw.height);
				if (raw.interlaced)
				{
					static const int starts[4] = {0, 4, 2, 1};
					static const int steps[4] = {8, 8, 4, 2};
					int row = 0;
					for (int pass = 0; pass < 4; pass++)
						for (int y = starts[pass]; y < raw.height; y += steps[pass])
							rowMap[row++] = y;
				}
				else
				{
					for (int y = 0; y < raw.height; y++)
						rowMap[y] = y;
				}

				int paletteSize = (int)(raw.palette.size() / 3);
				const uint8_t* palette = raw.palette.empty() ? nullptr : raw.palette.data();

				for (int n = 0; n < decoded; n++)
				{
					int index = indices[n];
					if (index == raw.transparentIndex || index >= paletteSize)
						continue;

					int x = raw.left + n % raw.width;
					int y = raw.top + rowMap[n / raw.width];
					if (x >= width || y >= height)
						continue;

					uint8_t* pixel = canvas.data() + ((size_t)y * width + x) * 4;
					const uint8_t* color = palette + index * 3;
					pixel[0] = color[0];
					pixel[1] = color[1];
					pixel[2] = color[2];
					pixel[3] = 255;
				}
			}

			DecodedFrame frame;
			frame.pixels = canvas;
			frame.delay = raw.delay;
			frame.left = raw.left;
			frame.top = raw.top;
			frame.width = raw.width;
			frame.height = raw.height;
			frame.disposal = raw.disposal;
			frame.interlaced = raw.interlaced;
			frames.push_back(std::move(frame));

			if (raw.disposal == 2)
			{
				int right = std::min(width, raw.left + raw.width);
				int bottom = std::min(height, raw.top + raw.height);
				for (int y = raw.top; y < bottom; y++)
					if (right > raw.left)
						std::memset(canvas.data() + ((size_t)y * width + raw.left) * 4, 0, (size_t)(right - raw.left) * 4);
			}
			else if (raw.disposal == 3 && !saved.empty())
			{
				canvas = saved;
			}
		}

		return true;
	}

	int GifDecoder::getWidth() const
	{
		return width;
	}

	int GifDecoder::getHeight() const
	{
		return height;
	}

	int GifDecoder::getLoopCount() const
	{
		return loopCount;
	}

	int GifDecoder::getFrameCount() const
	{
		return (int)frames.size();
	}

	int GifDecoder::getFrameDelay(int index) const
	{
		if (index < 0 || index >= (int)frames.size())
			return 0;
		return frames[index].delay;
	}

	int GifDecoder::getFrameDisposal(int index) const
	{
		if (index < 0 || index >= (int)frames.size())
			return 0;
		return frames[index].disposal;
	}

	int GifDecoder::getVersion() const
	{
		return version;
	}

	int GifDecoder::getBackgroundColor() const
	{
		return backgroundColor;
	}

	int GifDecoder::getAspectRatio() const
	{
		return aspectRatio;
	}

	int GifDecoder::getCommentCount() const
	{
		return (int)comments.size();
	}

	int GifDecoder::getCommentLength(int index) const
	{
		if (index < 0 || index >= (int)comments.size())
			return 0;
		return (int)comments[index].size();
	}

	bool GifDecoder::copyComment(int index, uint8_t* destination) const
	{
		if (destination == nullptr || index < 0 || index >= (int)comments.size())
			return false;
		std::memcpy(destination, comments[index].data(), comments[index].size());
		return true;
	}

	int GifDecoder::getFrameLeft(int index) const
	{
		if (index < 0 || index >= (int)frames.size())
			return 0;
		return frames[index].left;
	}

	int GifDecoder::getFrameTop(int index) const
	{
		if (index < 0 || index >= (int)frames.size())
			return 0;
		return frames[index].top;
	}

	int GifDecoder::getFrameWidth(int index) const
	{
		if (index < 0 || index >= (int)frames.size())
			return 0;
		return frames[index].width;
	}

	int GifDecoder::getFrameHeight(int index) const
	{
		if (index < 0 || index >= (int)frames.size())
			return 0;
		return frames[index].height;
	}

	bool GifDecoder::getFrameInterlaced(int index) const
	{
		if (index < 0 || index >= (int)frames.size())
			return false;
		return frames[index].interlaced;
	}

	bool GifDecoder::copyFrame(int index, uint8_t* destination) const
	{
		if (destination == nullptr || index < 0 || index >= (int)frames.size())
			return false;

		const std::vector<uint8_t>& pixels = frames[index].pixels;
		std::memcpy(destination, pixels.data(), pixels.size());
		return true;
	}

	const char* GifDecoder::getError() const
	{
		return error.c_str();
	}

	GifDecoder* createDecoder()
	{
		return new GifDecoder();
	}

	void destroyDecoder(GifDecoder* decoder)
	{
		delete decoder;
	}
}
