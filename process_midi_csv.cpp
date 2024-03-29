/*
 * VIC 20 registers
 * 0 low  tone: f =  3995/(255-x)  or   4330/(255-x) PAL
 * 1 mid  tone: f =  7990/(255-x)  or   8660/(255-x) PAL
 * 2 high tone: f = 15980/(255-x)  or  17320/(255-x) PAL
 *
 * min notes:
 * low tone:  x=128 → f=31.46  (midi 23, B0)
 *               or   f=34.09  (midi 25, C1#) PAL
 * mid tone:  x=128 → f=62.91  (midi 35, B1)
 *               or   f=68.19  (midi 37, C2#) PAL
 * high tone: x=128 → f=125.83 (midi 47, B2)
 *               or   f=136.38 (midi 48, C3#) PAL
 *
 * inverse formula: x = 255 - CLK/f
 *
 * see https://newt.phys.unsw.edu.au/jw/notes.html
*/


#include <iostream>
#include <cstdio>
#include <string>
#include <vector>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <map>
#include <set>
#include <cmath>
#include <algorithm>
using namespace std;

#define VIC_CLOCK 15980  // 17320 for PAL
const unsigned divisor[] = {4, 2, 1};
const unsigned min_tone[] = {24, 36, 48};

struct Note {
	unsigned time, note;
	bool on;
};
typedef vector<Note> Track;
typedef map<unsigned, Track> Song;
struct ToneMidi {
	unsigned channel, note, time;
};
typedef vector<ToneMidi> MultiTrack;
class NoteGenerator {
public:
	NoteGenerator(unsigned fs);
	void set_note(float f);
	uint8_t step();  // 0 or 1
private:
	const unsigned fs;
	unsigned count, limit;
	uint8_t out = 0;
};


float midi_2_freq(unsigned m) { return 440. * pow(2, ((int)m - 69) / 12.); }
float vic_2_freq(unsigned x, unsigned channel) { return (VIC_CLOCK / divisor[channel]) / (255. - x); }
int freq_2_vic(float f, unsigned channel) { int n = round(255 - (VIC_CLOCK / divisor[channel]) / f);  return n < 128 ? 128 : n > 254 ? 254 : n; }
unsigned str_to_num(const string &);  // throws
vector<string> split(const string &);
Song parse(ifstream &);
MultiTrack simplify(const Track &, unsigned id, bool keep_all_notes);
MultiTrack interleave(const MultiTrack&, const MultiTrack&);
void write_wav_file(const char *fname, unsigned fs, vector<uint8_t> const &data);


int main(int argc, char **argv) {
	if (argc != 5) {
		cerr << "Argument error" << endl;
		return 1;
	}
	ifstream f(argv[1]);  // midicsv output
	if (!f) throw runtime_error("Unable to read input file");
	Song song = parse(f);
	cout << "tracks: " << song.size() << endl;
	for (auto const &t: song)
		cout << "notes: " << t.second.size() << endl;
	// process song for single-note output for each track
	vector<MultiTrack> channels;
	unsigned id = 0;
	for (auto const &t: song) {
		auto ch = simplify(t.second, id, false);
		++id;
		cout << "ch: " << ch.size() << endl;
		//for (auto const &n: ch)	cout << "(" << n.note << "," << n.time << ")";	cout << endl;
		channels.push_back(ch);
	}
	if (song.size() != 2) {
		cerr << "Number of tracks is not 2" << endl;
		return 1;
	}
	// compute which track has lower notes
	unsigned min_note[2];
	for (unsigned i = 0; i < 2; ++i)
		min_note[i] = std::min_element(channels[i].cbegin(), channels[i].cend(), [](const auto &a, const auto &b){ return (a.note ? a.note : 200) < (b.note ? b.note : 200); })->note;
	// we want tracks sorted by octave
	if (min_note[1] < min_note[0]) {
		iter_swap(channels.begin(), channels.begin() + 1);
		std::swap(min_note[0], min_note[1]);
	}
	cout << min_note[0] << " " << min_note[1] << endl;
	// interleave the two channels and convert times to durations
	auto mixed = interleave(channels[0], channels[1]);
	// truncate
	mixed.resize(std::min(atoi(argv[4]), (int)mixed.size()));
	mixed.erase(mixed.begin(), mixed.begin() + atoi(argv[3]));
	mixed.push_back(ToneMidi{0, 0, 100});
	mixed.push_back(ToneMidi{1, 0, 100});

	// generate wave file (for debug purpose)
	const unsigned fs = 8000;
	vector<uint8_t> wave;
	NoteGenerator gen[] = {NoteGenerator(fs), NoteGenerator(fs)};
	for (const auto &m: mixed) {
		float freq = m.note ? vic_2_freq(freq_2_vic(midi_2_freq(m.note), m.channel + 1), m.channel + 1) : 0;
		gen[m.channel].set_note(freq);
		for (unsigned t = 0; t < m.time * 100; ++t) wave.push_back(gen[0].step() * 64 + gen[1].step() * 64);
	}
	write_wav_file(argv[2], fs, wave);
	// generate binary data for the VIC; every event is 2 bytes:
	//  1) bit 7 is the channel
	//     (bit 0..6) + 127 = value (resulting in 127 (off) .. 253 (max)) (254 is excluded because of the terminator)
	//  2) duration in 1/60 seconds (interrupt rate)
	//     if 0, the following event must be processed simultaneously
	//  - FF is the terminator
	vector<uint8_t> hex;
	for (const auto &m: mixed) {
		uint8_t note = m.note ? freq_2_vic(midi_2_freq(m.note), m.channel + 1) : 0;  // 0 or 128..254
		if (note == 254) note = 253;
		note = note ? note - 127 : 0;
		unsigned t = m.time, t8;  // 1 midi time = 1/60 tick
		if (t) {
			t = round(t * 0.75);
			if (!t) t = 1;
		}
		do {
			t8 = std::min(255u, t);
			hex.push_back(note);
			if (m.channel) hex.back() |= 128;
			hex.push_back(t8);
			t -= t8;
		} while (t8 == 255);
	}
	hex.push_back(0xFF);
	cout << "Encoded size: " << hex.size() << "\n" << endl;
	for (unsigned i = 0; i < hex.size(); i += 32) {
		printf("\thex ");
		for (unsigned j = 0; j < std::min((size_t)32, hex.size() - i); ++j)
			printf("%02X", hex[i + j]);
		printf("\n");
	}
}


vector<string> split(const string &s) {
	vector<string> result;
	char *dup = strdup(s.c_str());
	char *token = strtok(dup, ", ");
	while (token) {
		result.push_back(token);
		token = strtok(nullptr, ", ");
	}
	free(dup);
	return result;
}


unsigned str_to_num(const string &s) {  // throws
	char *endptr;
	auto n = strtoul(s.c_str(), &endptr, 10);
	if (*endptr) throw runtime_error("Invalid number: " + s);
	return n;
}


Song parse(ifstream &f) {
	string line;
	Song song;
	unsigned line_num = 0;
	auto throw_exc = [&line_num](){ throw runtime_error("Format error at line: " + to_string(line_num)); };
	while (getline(f, line)) {
		++line_num;
		if (!line.size()) continue;
		auto tok = split(line);
		if (tok.size() < 3) throw_exc();
		unsigned tr = str_to_num(tok[0]);
		if (!tr) continue;
		if (tok[2] == "Note_on_c" || tok[2] == "Note_off_c") {
			if (tok.size() != 6) throw_exc();
			song[tr].push_back(Note{ str_to_num(tok[1]), str_to_num(tok[4]),
				(tok[2] == "Note_on_c" && str_to_num(tok[5])) });
		}
		else if (tok[2] == "Control_c" && str_to_num(tok[4]) == 64) {  // sustain
			if (tok.size() != 6) throw_exc();
			song[tr].push_back(Note{ str_to_num(tok[1]), 255 /* special value */, str_to_num(tok[5]) >= 64 });
		}
	}
	return song;
}


MultiTrack simplify(const Track &tr, unsigned id, bool keep_all_notes) {
	MultiTrack ch;
	bool sustain = false;
	// set absolute times
	if (tr[0].time) ch.push_back(ToneMidi{ id, 0, 0 });
	if (!keep_all_notes) {
		for (auto const &note: tr)
			if (note.note != 255) ch.push_back(ToneMidi{ id, (note.on ? note.note : 0), note.time });
	}
	else {
		// at every instant, if multiple notes are playing, keep the higher one (but only as long as it's playing)
		set<unsigned> playing;
		for (auto const &note: tr) {
			if (note.note == 255) {
				sustain = note.on;
				if (!sustain) playing.clear();
			}
			else if (note.on) {
				if (playing.empty() || *playing.rbegin() < note.note)
					ch.push_back(ToneMidi{ id, note.note, note.time });
				if (sustain) playing.insert(note.note);
			}
			else {
				//if (!playing.empty() && note.note == *playing.rbegin()) playing.clear();
				playing.erase(note.note);
				ch.push_back(ToneMidi{ id, playing.empty() ? 0 : *playing.rbegin(), note.time });
			}
		}
	}
	// if more than one note starts at the same absolute time, keep the higher
	for (unsigned i = 0; i < ch.size() - 1; ++i) {
		if (!ch[i].note) continue;
		unsigned t = ch[i].time;
		for (unsigned j = i + 1; j < ch.size(); ++j) {
			if (ch[j].time != t) break;
			if (ch[j].note) {
				if (ch[j].note > ch[i].note) ch[i].note = ch[j].note;
				ch.erase(ch.begin() + j);
				--j;
			}
		}
	}
	// collapse multiple stops to only one
	for (unsigned i = 0; i < ch.size() - 1; ++i) {
		if (ch[i].note) continue;
		for (unsigned j = i + 1; j < ch.size(); ++j) {
			if (!ch[j].note) {
				ch.erase(ch.begin() + j);
				--j;
			}
			else break;
		}
	}
	// delete stops immediately followed by another note
	for (unsigned i = 0; i < ch.size() - 1; ++i)
		if (!ch[i].note && ch[i].time == ch[i + 1].time) {
			ch.erase(ch.begin() + i);
			--i;
		}
	return ch;
}


NoteGenerator::NoteGenerator(unsigned _fs): fs(_fs)
{}


void NoteGenerator::set_note(float f) {
	limit = f ? fs / (2 * f) : 0;
	if (count >= limit) count = 0;
}


uint8_t NoteGenerator::step() {
	if (!limit) return out;
	++count;
	if (count >= limit) {
		count = 0;
		out = !out;
	}
	return out;
}


MultiTrack interleave(const MultiTrack &ch0, const MultiTrack &ch1) {
	// first interleave channels with absolute times, sorted
	MultiTrack result;
	MultiTrack::const_iterator it0 = ch0.cbegin(), it1 = ch1.cbegin();
	while (it0 != ch0.cend() || it1 != ch1.cend()) {
		if (it0 == ch0.cend()) result.push_back(*it1++);
		else if (it1 == ch1.cend()) result.push_back(*it0++);
		else {
			if (it1->time < it0->time) result.push_back(*it1++);
			else result.push_back(*it0++);
		}
	}
	// then convert to durations
	for (auto it = result.begin(); it != result.end() - 1; ++it) it->time = (it+1)->time - it->time;
	result.back().time = 40;
	return result;
}


void write_wav_file(const char *fname, unsigned fs, vector<uint8_t> const &data) {
	static uint8_t header[] = { 'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'A', 'V', 'E',
		'f', 'm', 't', ' ', 16, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 8, 0,
		'd', 'a', 't', 'a', 0, 0, 0, 0 };
	*((uint32_t*)(header + 4)) = data.size() + 36;
	*((uint32_t*)(header + 24)) = fs;
	*((uint32_t*)(header + 28)) = fs;
	*((uint32_t*)(header + 40)) = data.size();
	FILE *f = fopen(fname, "wb");
	fwrite(header, 1, 44, f);
	if (fwrite(data.data(), 1, data.size(), f) != data.size()) throw runtime_error("Unable to write wav file");
	fclose(f);
}
