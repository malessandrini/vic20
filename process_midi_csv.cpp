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
#include <cmath>
#include <algorithm>
using namespace std;

#define VIC_CLOCK 15980  // 17320 for PAL
const unsigned divisor[] = {4, 2, 1};

struct Note {
	unsigned time, note;
	bool on;
};
struct Track {
	vector<Note> notes;
	// space for extra fields
};
struct Song {
	map<unsigned, Track> tracks;
	// space for extra fields
};
struct Tone {
	unsigned note, time;
};


unsigned str_to_num(const string &);  // throws
vector<string> split(const string &);
Song parse(ifstream &);
vector<Tone> simplify(const Track &);
float midi_2_freq(unsigned m) { return 440. * pow(2, (m - 69) / 12.); }
float vic_2_freq(unsigned x, unsigned channel) { return (VIC_CLOCK / divisor[channel]) / (255. - x); }
int freq_2_vic(float f, unsigned channel) { return (int)round(255 - (VIC_CLOCK / divisor[channel]) / f); }  // might be out of allowed range


int main(int argc, char **argv) {
	if (argc != 3) {
		cerr << "Argument error" << endl;
		return 1;
	}
	ifstream f(argv[1]);  // midicsv output
	if (!f) throw runtime_error("Unable to read input file");
	Song song = parse(f);
	cout << "tracks: " << song.tracks.size() << endl;
	for (auto const &t: song.tracks)
		cout << "notes: " << t.second.notes.size() << endl;
	// process song for single-note output for each track
	vector<vector<Tone>> channels;
	for (auto const &t: song.tracks) {
		auto ch = simplify(t.second);
		cout << "ch: " << ch.size() << endl;
		//for (auto const &n: ch)	cout << "(" << n.note << "," << n.time << ")";	cout << endl;
		channels.push_back(ch);
	}
	if (song.tracks.size() != 2) {
		cerr << "Number of tracks is not 2" << endl;
		return 1;
	}
	// compute which track has higher notes
	unsigned max_note[2], min_note[2];
	for (unsigned i = 0; i < 2; ++i) {
		max_note[i] = std::max_element(channels[i].cbegin(), channels[i].cend(), [](const auto &a, const auto &b){ return a.note < b.note; })->note;
		min_note[i] = std::min_element(channels[i].cbegin(), channels[i].cend(), [](const auto &a, const auto &b){ return (a.note ? a.note : 200) < (b.note ? b.note : 200); })->note;
	}
	cout << min_note[0] << "," << max_note[0] << " " << min_note[1] << "," << max_note[1] << endl;
	// we want tracks in order of octave
	if (min_note[1] < min_note[0]) iter_swap(channels.begin(), channels.begin() + 1);
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
			song.tracks[tr].notes.push_back(Note{ str_to_num(tok[1]), str_to_num(tok[4]),
				(tok[2] == "Note_on_c" && str_to_num(tok[5])) });
		}
	}
	return song;
}


vector<Tone> simplify(const Track &tr) {
	vector<Tone> ch;
	// set absolute times
	if (tr.notes[0].time) ch.push_back(Tone{ 0, 0 });
	for (auto const &note: tr.notes)
		ch.push_back(Tone{ (note.on ? note.note : 0), note.time });
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
	// test overlaps: note starting when another still playing -> keep the higher one
	bool on = false;
	unsigned curr = 0;
	for (auto &note: ch) {
		if (!note.note) on = false;
		else {
			if (on) {
				//cerr << "Warning: overlap at " << note.duration << endl;
				if (curr > note.note) note.note = curr;
				else curr = note.note;
			}
			else curr = note.note;
			on = true;
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
