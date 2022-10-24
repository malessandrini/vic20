#include <cstdio>
#include <cstdint>


int main() {
	for (uint8_t color = 1; color <=2; ++color) {
		uint8_t lut[256];
		for (int seq = 0; seq < 256; ++seq) {
			lut[seq] = 0;
			uint8_t tmp = seq;
			for (int p = 0; p < 4; ++p) {
				uint8_t v = tmp & 0x03;
				tmp >>= 2;
				if (v == color) ++lut[seq];
				else if (v) {
					lut[seq] = 0;
					break;
				}
			}
		}
		printf("lutseq%d\n", color);
		for (uint8_t row = 0, *ptr = lut; row < 8; ++row) {
			printf("\thex ");
			for (uint8_t i = 0; i < 32; ++i) printf("%02X", *ptr++);
			printf("\n");
		}
	}
}
