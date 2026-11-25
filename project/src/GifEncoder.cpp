#include "hxgif/GifEncoder.h"

#include <algorithm>
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

	GifEncoder::GifEncoder(int width, int height, int loopCount)
		: width(width), height(height), loopCount(loopCount), frameCount(0), finished(false)
	{
		writeHeader();
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

	bool GifEncoder::addFrame(const uint8_t* rgba, int delay)
	{
		if (finished || rgba == nullptr || width <= 0 || height <= 0)
			return false;

		size_t pixelCount = (size_t)width * (size_t)height;
		bool hasTransparency = false;

		std::unordered_map<uint32_t, long long> exact;
		exact.reserve(512);
		bool exactFits = true;

		for (size_t i = 0; i < pixelCount; i++)
		{
			const uint8_t* pixel = rgba + i * 4;
			if (pixel[3] < 128)
			{
				hasTransparency = true;
				continue;
			}
			if (exactFits)
			{
				uint32_t key = ((uint32_t)pixel[0] << 16) | ((uint32_t)pixel[1] << 8) | pixel[2];
				exact[key]++;
				if (exact.size() > 256)
					exactFits = false;
			}
		}

		int maxColors = hasTransparency ? 255 : 256;
		if (exact.size() > (size_t)maxColors)
			exactFits = false;

		std::vector<uint8_t> palette;
		std::vector<int> lookup(32768, -1);
		std::unordered_map<uint32_t, int> exactLookup;

		if (exactFits)
		{
			for (const auto& item : exact)
			{
				exactLookup[item.first] = (int)(palette.size() / 3);
				palette.push_back((uint8_t)(item.first >> 16));
				palette.push_back((uint8_t)(item.first >> 8));
				palette.push_back((uint8_t)item.first);
			}
		}
		else
		{
			std::vector<long long> histogram(32768 * 4, 0);
			for (size_t i = 0; i < pixelCount; i++)
			{
				const uint8_t* pixel = rgba + i * 4;
				if (pixel[3] < 128)
					continue;
				int key = ((pixel[0] >> 3) << 10) | ((pixel[1] >> 3) << 5) | (pixel[2] >> 3);
				histogram[key * 4] += pixel[0];
				histogram[key * 4 + 1] += pixel[1];
				histogram[key * 4 + 2] += pixel[2];
				histogram[key * 4 + 3]++;
			}

			std::vector<ColorEntry> entries;
			for (int key = 0; key < 32768; key++)
			{
				long long count = histogram[key * 4 + 3];
				if (count == 0)
					continue;
				ColorEntry entry;
				entry.r = (int)(histogram[key * 4] / count);
				entry.g = (int)(histogram[key * 4 + 1] / count);
				entry.b = (int)(histogram[key * 4 + 2] / count);
				entry.count = count;
				entries.push_back(entry);
			}

			medianCut(entries, maxColors, palette);

			for (int key = 0; key < 32768; key++)
			{
				long long count = histogram[key * 4 + 3];
				if (count == 0)
					continue;
				lookup[key] = nearestColor(palette, (int)(histogram[key * 4] / count), (int)(histogram[key * 4 + 1] / count), (int)(histogram[key * 4 + 2] / count));
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
		palette.resize((size_t)(1 << tableBits) * 3, 0);

		std::vector<uint8_t> indices(pixelCount);
		for (size_t i = 0; i < pixelCount; i++)
		{
			const uint8_t* pixel = rgba + i * 4;
			if (pixel[3] < 128)
			{
				indices[i] = (uint8_t)transparentIndex;
			}
			else if (exactFits)
			{
				uint32_t key = ((uint32_t)pixel[0] << 16) | ((uint32_t)pixel[1] << 8) | pixel[2];
				indices[i] = (uint8_t)exactLookup[key];
			}
			else
			{
				int key = ((pixel[0] >> 3) << 10) | ((pixel[1] >> 3) << 5) | (pixel[2] >> 3);
				indices[i] = (uint8_t)lookup[key];
			}
		}

		int centiseconds = std::max(0, std::min(65535, (delay + 5) / 10));
		int disposal = 2;

		writeByte(0x21);
		writeByte(0xF9);
		writeByte(4);
		writeByte((disposal << 2) | (hasTransparency ? 1 : 0));
		writeShort(centiseconds);
		writeByte(hasTransparency ? transparentIndex : 0);
		writeByte(0);

		writeByte(0x2C);
		writeShort(0);
		writeShort(0);
		writeShort(width);
		writeShort(height);
		writeByte(0x80 | (tableBits - 1));
		output.insert(output.end(), palette.begin(), palette.end());

		int minCodeSize = std::max(2, tableBits);
		writeByte(minCodeSize);

		std::vector<uint8_t> compressed;
		compress(indices, minCodeSize, compressed);
		output.insert(output.end(), compressed.begin(), compressed.end());

		frameCount++;
		return true;
	}

	void GifEncoder::finish()
	{
		if (finished)
			return;
		writeByte(0x3B);
		finished = true;
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

	GifEncoder* createEncoder(int width, int height, int loopCount)
	{
		return new GifEncoder(width, height, loopCount);
	}

	void destroyEncoder(GifEncoder* encoder)
	{
		delete encoder;
	}
}
