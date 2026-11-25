#include "hxgif/GifEncoder.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <unordered_map>

namespace hxgif
{
	namespace
	{
		struct ColorEntry
		{
			int r;
			int g;
			int b;
			long long count;
		};

		struct Box
		{
			int begin;
			int end;
		};

		struct BitWriter
		{
			std::vector<uint8_t> bytes;
			uint32_t buffer = 0;
			int count = 0;

			void write(int code, int size)
			{
				buffer |= (uint32_t)code << count;
				count += size;
				while (count >= 8)
				{
					bytes.push_back((uint8_t)(buffer & 0xFF));
					buffer >>= 8;
					count -= 8;
				}
			}

			void flush()
			{
				if (count > 0)
				{
					bytes.push_back((uint8_t)(buffer & 0xFF));
					buffer = 0;
					count = 0;
				}
			}
		};

		int channel(const ColorEntry& entry, int axis)
		{
			return axis == 0 ? entry.r : (axis == 1 ? entry.g : entry.b);
		}

		void medianCut(std::vector<ColorEntry>& entries, int maxColors, std::vector<uint8_t>& palette)
		{
			std::vector<Box> boxes;
			boxes.push_back({0, (int)entries.size()});

			while ((int)boxes.size() < maxColors)
			{
				int bestBox = -1;
				int bestAxis = 0;
				long long bestScore = -1;

				for (int i = 0; i < (int)boxes.size(); i++)
				{
					const Box& box = boxes[i];
					if (box.end - box.begin < 2)
						continue;

					int minimum[3] = {255, 255, 255};
					int maximum[3] = {0, 0, 0};
					long long total = 0;
					for (int e = box.begin; e < box.end; e++)
					{
						for (int axis = 0; axis < 3; axis++)
						{
							int value = channel(entries[e], axis);
							minimum[axis] = std::min(minimum[axis], value);
							maximum[axis] = std::max(maximum[axis], value);
						}
						total += entries[e].count;
					}

					int axis = 0;
					int range = maximum[0] - minimum[0];
					for (int a = 1; a < 3; a++)
					{
						if (maximum[a] - minimum[a] > range)
						{
							range = maximum[a] - minimum[a];
							axis = a;
						}
					}

					long long score = (long long)range * total;
					if (range > 0 && score > bestScore)
					{
						bestScore = score;
						bestBox = i;
						bestAxis = axis;
					}
				}

				if (bestBox < 0)
					break;

				Box box = boxes[bestBox];
				std::sort(entries.begin() + box.begin, entries.begin() + box.end, [bestAxis](const ColorEntry& a, const ColorEntry& b) {
					return channel(a, bestAxis) < channel(b, bestAxis);
				});

				long long total = 0;
				for (int e = box.begin; e < box.end; e++)
					total += entries[e].count;

				long long half = total / 2;
				long long accumulated = 0;
				int split = box.begin + 1;
				for (int e = box.begin; e < box.end - 1; e++)
				{
					accumulated += entries[e].count;
					split = e + 1;
					if (accumulated >= half)
						break;
				}

				boxes[bestBox] = {box.begin, split};
				boxes.push_back({split, box.end});
			}

			palette.clear();
			for (const Box& box : boxes)
			{
				long long r = 0;
				long long g = 0;
				long long b = 0;
				long long total = 0;
				for (int e = box.begin; e < box.end; e++)
				{
					r += (long long)entries[e].r * entries[e].count;
					g += (long long)entries[e].g * entries[e].count;
					b += (long long)entries[e].b * entries[e].count;
					total += entries[e].count;
				}
				if (total == 0)
					total = 1;
				palette.push_back((uint8_t)((r + total / 2) / total));
				palette.push_back((uint8_t)((g + total / 2) / total));
				palette.push_back((uint8_t)((b + total / 2) / total));
			}
		}

		int nearestColor(const std::vector<uint8_t>& palette, int r, int g, int b)
		{
			int best = 0;
			int bestDistance = 0x7FFFFFFF;
			int count = (int)(palette.size() / 3);
			for (int i = 0; i < count; i++)
			{
				int dr = palette[i * 3] - r;
				int dg = palette[i * 3 + 1] - g;
				int db = palette[i * 3 + 2] - b;
				int distance = dr * dr * 2 + dg * dg * 4 + db * db * 3;
				if (distance < bestDistance)
				{
					bestDistance = distance;
					best = i;
					if (distance == 0)
						break;
				}
			}
			return best;
		}

		int clampChannel(float value)
		{
			int result = (int)std::lround(value);
			return result < 0 ? 0 : (result > 255 ? 255 : result);
		}

		void ditherIndices(const std::vector<int>& colors, int regionWidth, int regionHeight, const std::vector<uint8_t>& palette, std::vector<int>& lookup, int transparentIndex, std::vector<uint8_t>& indices)
		{
			size_t stride = (size_t)(regionWidth + 2) * 3;
			std::vector<float> current(stride, 0.0f);
			std::vector<float> next(stride, 0.0f);

			for (int y = 0; y < regionHeight; y++)
			{
				for (int x = 0; x < regionWidth; x++)
				{
					size_t n = (size_t)y * regionWidth + x;
					int color = colors[n];
					if (color < 0)
					{
						indices[n] = (uint8_t)transparentIndex;
						continue;
					}

					size_t e = (size_t)(x + 1) * 3;
					int r = clampChannel(((color >> 16) & 0xFF) + current[e]);
					int g = clampChannel(((color >> 8) & 0xFF) + current[e + 1]);
					int b = clampChannel((color & 0xFF) + current[e + 2]);

					int key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
					int index = lookup[key];
					if (index < 0)
					{
						index = nearestColor(palette, r, g, b);
						lookup[key] = index;
					}
					indices[n] = (uint8_t)index;

					float errorR = (float)(r - palette[index * 3]);
					float errorG = (float)(g - palette[index * 3 + 1]);
					float errorB = (float)(b - palette[index * 3 + 2]);

					current[e + 3] += errorR * 7.0f / 16.0f;
					current[e + 4] += errorG * 7.0f / 16.0f;
					current[e + 5] += errorB * 7.0f / 16.0f;
					next[e - 3] += errorR * 3.0f / 16.0f;
					next[e - 2] += errorG * 3.0f / 16.0f;
					next[e - 1] += errorB * 3.0f / 16.0f;
					next[e] += errorR * 5.0f / 16.0f;
					next[e + 1] += errorG * 5.0f / 16.0f;
					next[e + 2] += errorB * 5.0f / 16.0f;
					next[e + 3] += errorR / 16.0f;
					next[e + 4] += errorG / 16.0f;
					next[e + 5] += errorB / 16.0f;
				}

				current.swap(next);
				std::fill(next.begin(), next.end(), 0.0f);
			}
		}

		void compress(const std::vector<uint8_t>& indices, int minCodeSize, std::vector<uint8_t>& result)
		{
			int clearCode = 1 << minCodeSize;
			int endCode = clearCode + 1;
			int codeSize = minCodeSize + 1;
			int nextCode = clearCode + 2;

			std::unordered_map<uint32_t, int> dictionary;
			dictionary.reserve(8192);

			BitWriter writer;
			writer.write(clearCode, codeSize);

			int current = indices[0];
			for (size_t i = 1; i < indices.size(); i++)
			{
				int value = indices[i];
				uint32_t key = ((uint32_t)current << 8) | (uint32_t)value;
				auto found = dictionary.find(key);
				if (found != dictionary.end())
				{
					current = found->second;
					continue;
				}

				writer.write(current, codeSize);
				dictionary[key] = nextCode++;

				if (nextCode > (1 << codeSize) && codeSize < 12)
					codeSize++;

				if (nextCode == 4096)
				{
					writer.write(clearCode, codeSize);
					dictionary.clear();
					codeSize = minCodeSize + 1;
					nextCode = clearCode + 2;
				}

				current = value;
			}

			writer.write(current, codeSize);
			if (nextCode == (1 << codeSize) && codeSize < 12)
				codeSize++;
			writer.write(endCode, codeSize);
			writer.flush();

			result.clear();
			size_t position = 0;
			while (position < writer.bytes.size())
			{
				size_t size = std::min((size_t)255, writer.bytes.size() - position);
				result.push_back((uint8_t)size);
				result.insert(result.end(), writer.bytes.begin() + position, writer.bytes.begin() + position + size);
				position += size;
			}
			result.push_back(0);
		}
	}

	GifEncoder::GifEncoder(int width, int height, int loopCount, bool optimize, bool dither, int alphaThreshold)
		: width(width), height(height), loopCount(loopCount), frameCount(0), finished(false), optimize(optimize), dither(dither),
		  alphaThreshold(std::max(1, std::min(255, alphaThreshold))), hasPending(false), pendingDelay(0)
	{
		writeHeader();
		if (optimize)
			canvas.assign((size_t)width * (size_t)height * 4, 0);
	}

	void GifEncoder::writeByte(int value)
	{
		output.push_back((uint8_t)(value & 0xFF));
	}

	void GifEncoder::writeShort(int value)
	{
		writeByte(value);
		writeByte(value >> 8);
	}

	void GifEncoder::writeHeader()
	{
		const char* signature = "GIF89a";
		output.insert(output.end(), signature, signature + 6);
		writeShort(width);
		writeShort(height);
		writeByte(0x70);
		writeByte(0);
		writeByte(0);

		if (loopCount >= 0)
		{
			writeByte(0x21);
			writeByte(0xFF);
			writeByte(11);
			const char* identifier = "NETSCAPE2.0";
			output.insert(output.end(), identifier, identifier + 11);
			writeByte(3);
			writeByte(1);
			writeShort(loopCount);
			writeByte(0);
		}
	}

	bool GifEncoder::addComment(const uint8_t* text, int length)
	{
		if (finished || text == nullptr || length < 0)
			return false;
		if (length == 0)
			return true;

		writeByte(0x21);
		writeByte(0xFE);
		int position = 0;
		while (position < length)
		{
			int size = std::min(255, length - position);
			writeByte(size);
			output.insert(output.end(), text + position, text + position + size);
			position += size;
		}
		writeByte(0);
		return true;
	}

	void GifEncoder::normalize(const uint8_t* rgba, std::vector<uint8_t>& result) const
	{
		size_t size = (size_t)width * (size_t)height * 4;
		result.resize(size);
		for (size_t position = 0; position < size; position += 4)
		{
			if (rgba[position + 3] < alphaThreshold)
			{
				result[position] = 0;
				result[position + 1] = 0;
				result[position + 2] = 0;
				result[position + 3] = 0;
			}
			else
			{
				result[position] = rgba[position];
				result[position + 1] = rgba[position + 1];
				result[position + 2] = rgba[position + 2];
				result[position + 3] = 255;
			}
		}
	}

	bool GifEncoder::addFrame(const uint8_t* rgba, int delay)
	{
		if (finished || rgba == nullptr || width <= 0 || height <= 0)
			return false;

		std::vector<uint8_t> frame;
		normalize(rgba, frame);

		if (!optimize)
		{
			writeFrame(frame, delay, 2, 0, 0, width, height, nullptr);
		}
		else
		{
			if (hasPending)
				flushPending(&frame);
			pending.swap(frame);
			pendingDelay = delay;
			hasPending = true;
		}

		frameCount++;
		return true;
	}

	void GifEncoder::flushPending(const std::vector<uint8_t>* next)
	{
		bool needsClear = false;
		if (next != nullptr)
		{
			for (size_t position = 3; position < pending.size(); position += 4)
			{
				if ((*next)[position] == 0 && pending[position] != 0)
				{
					needsClear = true;
					break;
				}
			}
		}

		if (needsClear)
		{
			writeFrame(pending, pendingDelay, 2, 0, 0, width, height, &canvas);
			std::fill(canvas.begin(), canvas.end(), 0);
		}
		else
		{
			int left = width;
			int top = height;
			int right = -1;
			int bottom = -1;
			for (int y = 0; y < height; y++)
			{
				for (int x = 0; x < width; x++)
				{
					size_t position = ((size_t)y * width + x) * 4;
					if (std::memcmp(pending.data() + position, canvas.data() + position, 4) != 0)
					{
						left = std::min(left, x);
						right = std::max(right, x);
						top = std::min(top, y);
						bottom = std::max(bottom, y);
					}
				}
			}

			if (right < 0)
			{
				left = 0;
				top = 0;
				right = 0;
				bottom = 0;
			}

			writeFrame(pending, pendingDelay, 1, left, top, right - left + 1, bottom - top + 1, &canvas);
			canvas.swap(pending);
		}

		hasPending = false;
	}

	void GifEncoder::writeFrame(const std::vector<uint8_t>& frame, int delay, int disposal, int regionX, int regionY, int regionWidth, int regionHeight, const std::vector<uint8_t>* compare)
	{
		size_t count = (size_t)regionWidth * (size_t)regionHeight;
		std::vector<int> colors(count);
		bool hasTransparency = false;

		std::unordered_map<uint32_t, int> exact;
		exact.reserve(512);
		bool exactFits = true;

		for (int row = 0; row < regionHeight; row++)
		{
			for (int column = 0; column < regionWidth; column++)
			{
				size_t n = (size_t)row * regionWidth + column;
				size_t position = ((size_t)(regionY + row) * width + regionX + column) * 4;
				const uint8_t* pixel = frame.data() + position;
				if (pixel[3] == 0 || (compare != nullptr && std::memcmp(pixel, compare->data() + position, 4) == 0))
				{
					colors[n] = -1;
					hasTransparency = true;
					continue;
				}

				uint32_t key = ((uint32_t)pixel[0] << 16) | ((uint32_t)pixel[1] << 8) | pixel[2];
				colors[n] = (int)key;
				if (exactFits && exact.find(key) == exact.end())
				{
					int index = (int)exact.size();
					exact[key] = index;
					if (exact.size() > 256)
						exactFits = false;
				}
			}
		}

		int maxColors = hasTransparency ? 255 : 256;
		if (exact.size() > (size_t)maxColors)
			exactFits = false;

		std::vector<uint8_t> palette;
		std::vector<int> lookup;

		if (exactFits)
		{
			palette.resize(exact.size() * 3);
			for (const auto& item : exact)
			{
				palette[item.second * 3] = (uint8_t)(item.first >> 16);
				palette[item.second * 3 + 1] = (uint8_t)(item.first >> 8);
				palette[item.second * 3 + 2] = (uint8_t)item.first;
			}
		}
		else
		{
			std::vector<long long> histogram(32768 * 4, 0);
			for (size_t i = 0; i < count; i++)
			{
				int color = colors[i];
				if (color < 0)
					continue;
				int r = (color >> 16) & 0xFF;
				int g = (color >> 8) & 0xFF;
				int b = color & 0xFF;
				int key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
				histogram[key * 4] += r;
				histogram[key * 4 + 1] += g;
				histogram[key * 4 + 2] += b;
				histogram[key * 4 + 3]++;
			}

			std::vector<ColorEntry> entries;
			for (int key = 0; key < 32768; key++)
			{
				long long total = histogram[key * 4 + 3];
				if (total == 0)
					continue;
				ColorEntry entry;
				entry.r = (int)(histogram[key * 4] / total);
				entry.g = (int)(histogram[key * 4 + 1] / total);
				entry.b = (int)(histogram[key * 4 + 2] / total);
				entry.count = total;
				entries.push_back(entry);
			}

			medianCut(entries, maxColors, palette);

			lookup.assign(32768, -1);
			for (int key = 0; key < 32768; key++)
			{
				long long total = histogram[key * 4 + 3];
				if (total == 0)
					continue;
				lookup[key] = nearestColor(palette, (int)(histogram[key * 4] / total), (int)(histogram[key * 4 + 1] / total), (int)(histogram[key * 4 + 2] / total));
			}
		}

		int colorCount = (int)(palette.size() / 3);
		int transparentIndex = -1;
		if (hasTransparency)
		{
			transparentIndex = colorCount;
			palette.push_back(0);
			palette.push_back(0);
			palette.push_back(0);
			colorCount++;
		}

		int tableBits = 1;
		while ((1 << tableBits) < colorCount)
			tableBits++;

		std::vector<uint8_t> indices(count);
		if (exactFits)
		{
			for (size_t i = 0; i < count; i++)
				indices[i] = (uint8_t)(colors[i] < 0 ? transparentIndex : exact[(uint32_t)colors[i]]);
		}
		else if (dither)
		{
			ditherIndices(colors, regionWidth, regionHeight, palette, lookup, transparentIndex, indices);
		}
		else
		{
			for (size_t i = 0; i < count; i++)
			{
				int color = colors[i];
				if (color < 0)
				{
					indices[i] = (uint8_t)transparentIndex;
					continue;
				}
				int key = ((((color >> 16) & 0xFF) >> 3) << 10) | ((((color >> 8) & 0xFF) >> 3) << 5) | ((color & 0xFF) >> 3);
				indices[i] = (uint8_t)lookup[key];
			}
		}

		palette.resize((size_t)(1 << tableBits) * 3, 0);

		int centiseconds = std::max(0, std::min(65535, (delay + 5) / 10));

		writeByte(0x21);
		writeByte(0xF9);
		writeByte(4);
		writeByte((disposal << 2) | (hasTransparency ? 1 : 0));
		writeShort(centiseconds);
		writeByte(hasTransparency ? transparentIndex : 0);
		writeByte(0);

		writeByte(0x2C);
		writeShort(regionX);
		writeShort(regionY);
		writeShort(regionWidth);
		writeShort(regionHeight);
		writeByte(0x80 | (tableBits - 1));
		output.insert(output.end(), palette.begin(), palette.end());

		int minCodeSize = std::max(2, tableBits);
		writeByte(minCodeSize);

		std::vector<uint8_t> compressed;
		compress(indices, minCodeSize, compressed);
		output.insert(output.end(), compressed.begin(), compressed.end());
	}

	void GifEncoder::finish()
	{
		if (finished)
			return;
		if (hasPending)
			flushPending(nullptr);
		writeByte(0x3B);
		finished = true;
		canvas.clear();
		canvas.shrink_to_fit();
		pending.clear();
		pending.shrink_to_fit();
	}

	int GifEncoder::getWidth() const
	{
		return width;
	}

	int GifEncoder::getHeight() const
	{
		return height;
	}

	int GifEncoder::getFrameCount() const
	{
		return frameCount;
	}

	int GifEncoder::getSize() const
	{
		return (int)output.size();
	}

	bool GifEncoder::copyOutput(uint8_t* destination) const
	{
		if (destination == nullptr)
			return false;
		std::memcpy(destination, output.data(), output.size());
		return true;
	}

	GifEncoder* createEncoder(int width, int height, int loopCount, bool optimize, bool dither, int alphaThreshold)
	{
		return new GifEncoder(width, height, loopCount, optimize, dither, alphaThreshold);
	}

	void destroyEncoder(GifEncoder* encoder)
	{
		delete encoder;
	}
}
