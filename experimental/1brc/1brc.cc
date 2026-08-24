#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <format>
#include <iostream>
#include <limits>
#include <string_view>
#include <thread>
#include <vector>

#include "hwy/highway.h"
#include "hwy/contrib/thread_pool/topology.h"
#include "third_party/mph/mph.h"

namespace hn = hwy::HWY_NAMESPACE;

using std::literals::operator""sv;
using Clock = std::chrono::high_resolution_clock;

// Records are scanned a 64 byte window at a time; the window is the unit the
// inner loop walks with 64 bit masks, so it is independent of the vector
// width. `BitsFromMask` needs at most 64 lanes, hence the cap.
constexpr size_t kWindow = 64;
const hn::CappedTag<uint8_t, kWindow> kTag;
const auto broadcasted = Set(kTag, ';');
const auto broadcasted_nl = Set(kTag, '\n');

// Positions of `c` inside the 64 byte window at `p`, one bit per byte.
static HWY_INLINE uint64_t WindowMask(const char *p,
                                      hn::VFromD<decltype(kTag)> c) {
  const size_t lanes = hn::Lanes(kTag);
  uint64_t bits = 0;
  for (size_t off = 0; off < kWindow; off += lanes) {
    const auto v = LoadU(kTag, reinterpret_cast<const uint8_t *>(p + off));
    bits |= BitsFromMask(kTag, Eq(c, v)) << off;
  }
  return bits;
}

struct Record {
  int sum;
  int count;
  int min;
  int max;
};

// Returns id for given city name.
static int city_id(const char *name, size_t len);

// Returns name for given city id.
static std::string_view city_name(int id);

// Return total number of cities.
static std::size_t city_count();

int main(int argc, char *agrv[]) {
  auto tik = Clock::now();

  const auto n_threads = std::thread::hardware_concurrency();

  hwy::LogicalProcessorSet lps;
  lps.Set(n_threads - 1);
  hwy::SetThreadAffinity(lps);

  int fd = open("measurements.txt", O_RDONLY);
  struct stat file_stat;
  fstat(fd, &file_stat);

  size_t file_size = file_stat.st_size;
  const char *data = reinterpret_cast<const char *>(
      mmap(nullptr, file_size, PROT_READ, MAP_PRIVATE, fd, 0));

  // Min/max start at their identity values; zero-initialized records would
  // silently report 0 for a city whose readings never cross zero. The `min`
  // field accumulates max(-value), so its identity is INT_MIN as well.
  std::vector<std::vector<Record>> records(
      n_threads,
      std::vector<Record>(city_count(),
                          Record{0, 0, std::numeric_limits<int>::min(),
                                 std::numeric_limits<int>::min()}));
  size_t chunk_size = file_size / n_threads;

  {
    std::vector<std::jthread> threads;
    const char *end;
    const char *file_end = data + file_size;
    for (int tid = 0; tid < n_threads; ++tid) {
      end = data + chunk_size;
      while ((end < file_end) && (*end != '\n'))
        ++end;

      threads.emplace_back(std::jthread{
          [tid, &records](const char *data, const char *end) {
            hwy::LogicalProcessorSet lps;
            lps.Set(tid);
            hwy::SetThreadAffinity(lps);

            Record *const recs = records[tid].data();

            for (;;) {
              if (data >= end) {
                break;
              }

              // Separator and newline positions as bit masks over the
              // window. Keeping them in general purpose registers lets the
              // loop below walk records with `blsr`, so nothing on the
              // loop-carried dependency chain touches memory.
              uint64_t eols = WindowMask(data, broadcasted_nl);
              if (eols == 0) {
                // A window without a newline holds no complete record, and a
                // record never spans one: this is the end of the data.
                break;
              }
              uint64_t seps = WindowMask(data, broadcasted);

              size_t start = 0;
              do {
                const size_t p1 = hwy::Num0BitsBelowLS1Bit_Nonzero64(seps);
                seps &= seps - 1;
                const size_t p2 = hwy::Num0BitsBelowLS1Bit_Nonzero64(eols);
                eols &= eols - 1;

                auto &rec = recs[city_id(data + start, p1 - start)];

                // Branchless parse of "[-]d[d].d". The digit positions follow
                // from the separator and newline offsets, so this whole block
                // hangs off the chain instead of extending it.
                uint64_t w;
                __builtin_memcpy(&w, data + p1 + 1, sizeof(w));
                const int64_t sgn = (static_cast<int64_t>(~w) << 59) >> 63;
                const uint64_t digits =
                    ((w & ~static_cast<uint64_t>(sgn & 0xFF))
                     << (48 - 8 * (p2 - p1))) &
                    0x0F000F0F00ULL;
                const uint64_t absv =
                    ((digits * 0x640a0001ULL) >> 32) & 0x3FFULL;
                const int val = static_cast<int>(
                    (absv ^ static_cast<uint64_t>(sgn)) -
                    static_cast<uint64_t>(sgn));

                rec.max = std::max(rec.max, val);
                rec.min = std::max(rec.min, -val);
                rec.sum += val;
                rec.count += 1;
                start = p2 + 1;
              } while (eols);

              data += start;
            }
          },
          data, end});
      data = end + 1;
    }
  }

  // Gather results from all the threads. Sums are merged in 64 bits: the
  // per-thread int32 sums cannot overflow, but the merged total of ~2.4M
  // readings per city has under 2.2x headroom in tenths of a degree.
  std::vector<int64_t> sums(city_count());
  for (int j = 0; j < records[0].size(); ++j) {
    sums[j] = records[0][j].sum;
  }
  for (int i = 1; i < records.size(); ++i) {
    for (int j = 0; j < records[0].size(); ++j) {
      records[0][j].count += records[i][j].count;
      sums[j] += records[i][j].sum;
      records[0][j].max = std::max(records[0][j].max, records[i][j].max);
      records[0][j].min = std::max(records[0][j].min, records[i][j].min);
    }
  }

  std::cout << "{";

  bool is_first = true;
  for (int i = 0; i < records[0].size(); ++i) {
    const auto &rec = records[0][i];
    const auto &name = city_name(i);
    if (is_first) {
      std::cout << std::format("{}={:.1f}/{:.1f}/{:.1f}", name, -rec.min / 10.0,
                               sums[i] / 10.0 / rec.count, rec.max / 10.0);
      is_first = false;
    } else {
      std::cout << std::format(", {}={:.1f}/{:.1f}/{:.1f}", name,
                               -rec.min / 10.0, sums[i] / 10.0 / rec.count,
                               rec.max / 10.0);
    }
  }

  std::cout << "}\n";

  auto tok = Clock::now();
  std::cerr << "Time used: " << std::chrono::duration<double>(tok - tik)
            << std::endl;

  return 0;
}

static constexpr auto _names = std::array{
    "Abha"sv,
    "Abidjan"sv,
    "Abéché"sv,
    "Accra"sv,
    "Addis Ababa"sv,
    "Adelaide"sv,
    "Aden"sv,
    "Ahvaz"sv,
    "Albuquerque"sv,
    "Alexandra"sv,
    "Alexandria"sv,
    "Algiers"sv,
    "Alice Springs"sv,
    "Almaty"sv,
    "Amsterdam"sv,
    "Anadyr"sv,
    "Anchorage"sv,
    "Andorra la Vella"sv,
    "Ankara"sv,
    "Antananarivo"sv,
    "Antsiranana"sv,
    "Arkhangelsk"sv,
    "Ashgabat"sv,
    "Asmara"sv,
    "Assab"sv,
    "Astana"sv,
    "Athens"sv,
    "Atlanta"sv,
    "Auckland"sv,
    "Austin"sv,
    "Baghdad"sv,
    "Baguio"sv,
    "Baku"sv,
    "Baltimore"sv,
    "Bamako"sv,
    "Bangkok"sv,
    "Bangui"sv,
    "Banjul"sv,
    "Barcelona"sv,
    "Bata"sv,
    "Batumi"sv,
    "Beijing"sv,
    "Beirut"sv,
    "Belgrade"sv,
    "Belize City"sv,
    "Benghazi"sv,
    "Bergen"sv,
    "Berlin"sv,
    "Bilbao"sv,
    "Birao"sv,
    "Bishkek"sv,
    "Bissau"sv,
    "Blantyre"sv,
    "Bloemfontein"sv,
    "Boise"sv,
    "Bordeaux"sv,
    "Bosaso"sv,
    "Boston"sv,
    "Bouaké"sv,
    "Bratislava"sv,
    "Brazzaville"sv,
    "Bridgetown"sv,
    "Brisbane"sv,
    "Brussels"sv,
    "Bucharest"sv,
    "Budapest"sv,
    "Bujumbura"sv,
    "Bulawayo"sv,
    "Burnie"sv,
    "Busan"sv,
    "Cabo San Lucas"sv,
    "Cairns"sv,
    "Cairo"sv,
    "Calgary"sv,
    "Canberra"sv,
    "Cape Town"sv,
    "Changsha"sv,
    "Charlotte"sv,
    "Chiang Mai"sv,
    "Chicago"sv,
    "Chihuahua"sv,
    "Chittagong"sv,
    "Chișinău"sv,
    "Chongqing"sv,
    "Christchurch"sv,
    "City of San Marino"sv,
    "Colombo"sv,
    "Columbus"sv,
    "Conakry"sv,
    "Copenhagen"sv,
    "Cotonou"sv,
    "Cracow"sv,
    "Da Lat"sv,
    "Da Nang"sv,
    "Dakar"sv,
    "Dallas"sv,
    "Damascus"sv,
    "Dampier"sv,
    "Dar es Salaam"sv,
    "Darwin"sv,
    "Denpasar"sv,
    "Denver"sv,
    "Detroit"sv,
    "Dhaka"sv,
    "Dikson"sv,
    "Dili"sv,
    "Djibouti"sv,
    "Dodoma"sv,
    "Dolisie"sv,
    "Douala"sv,
    "Dubai"sv,
    "Dublin"sv,
    "Dunedin"sv,
    "Durban"sv,
    "Dushanbe"sv,
    "Edinburgh"sv,
    "Edmonton"sv,
    "El Paso"sv,
    "Entebbe"sv,
    "Erbil"sv,
    "Erzurum"sv,
    "Fairbanks"sv,
    "Fianarantsoa"sv,
    "Flores,  Petén"sv,
    "Frankfurt"sv,
    "Fresno"sv,
    "Fukuoka"sv,
    "Gaborone"sv,
    "Gabès"sv,
    "Gagnoa"sv,
    "Gangtok"sv,
    "Garissa"sv,
    "Garoua"sv,
    "George Town"sv,
    "Ghanzi"sv,
    "Gjoa Haven"sv,
    "Guadalajara"sv,
    "Guangzhou"sv,
    "Guatemala City"sv,
    "Halifax"sv,
    "Hamburg"sv,
    "Hamilton"sv,
    "Hanga Roa"sv,
    "Hanoi"sv,
    "Harare"sv,
    "Harbin"sv,
    "Hargeisa"sv,
    "Hat Yai"sv,
    "Havana"sv,
    "Helsinki"sv,
    "Heraklion"sv,
    "Hiroshima"sv,
    "Ho Chi Minh City"sv,
    "Hobart"sv,
    "Hong Kong"sv,
    "Honiara"sv,
    "Honolulu"sv,
    "Houston"sv,
    "Ifrane"sv,
    "Indianapolis"sv,
    "Iqaluit"sv,
    "Irkutsk"sv,
    "Istanbul"sv,
    "Jacksonville"sv,
    "Jakarta"sv,
    "Jayapura"sv,
    "Jerusalem"sv,
    "Johannesburg"sv,
    "Jos"sv,
    "Juba"sv,
    "Kabul"sv,
    "Kampala"sv,
    "Kandi"sv,
    "Kankan"sv,
    "Kano"sv,
    "Kansas City"sv,
    "Karachi"sv,
    "Karonga"sv,
    "Kathmandu"sv,
    "Khartoum"sv,
    "Kingston"sv,
    "Kinshasa"sv,
    "Kolkata"sv,
    "Kuala Lumpur"sv,
    "Kumasi"sv,
    "Kunming"sv,
    "Kuopio"sv,
    "Kuwait City"sv,
    "Kyiv"sv,
    "Kyoto"sv,
    "La Ceiba"sv,
    "La Paz"sv,
    "Lagos"sv,
    "Lahore"sv,
    "Lake Havasu City"sv,
    "Lake Tekapo"sv,
    "Las Palmas de Gran Canaria"sv,
    "Las Vegas"sv,
    "Launceston"sv,
    "Lhasa"sv,
    "Libreville"sv,
    "Lisbon"sv,
    "Livingstone"sv,
    "Ljubljana"sv,
    "Lodwar"sv,
    "Lomé"sv,
    "London"sv,
    "Los Angeles"sv,
    "Louisville"sv,
    "Luanda"sv,
    "Lubumbashi"sv,
    "Lusaka"sv,
    "Luxembourg City"sv,
    "Lviv"sv,
    "Lyon"sv,
    "Madrid"sv,
    "Mahajanga"sv,
    "Makassar"sv,
    "Makurdi"sv,
    "Malabo"sv,
    "Malé"sv,
    "Managua"sv,
    "Manama"sv,
    "Mandalay"sv,
    "Mango"sv,
    "Manila"sv,
    "Maputo"sv,
    "Marrakesh"sv,
    "Marseille"sv,
    "Maun"sv,
    "Medan"sv,
    "Mek'ele"sv,
    "Melbourne"sv,
    "Memphis"sv,
    "Mexicali"sv,
    "Mexico City"sv,
    "Miami"sv,
    "Milan"sv,
    "Milwaukee"sv,
    "Minneapolis"sv,
    "Minsk"sv,
    "Mogadishu"sv,
    "Mombasa"sv,
    "Monaco"sv,
    "Moncton"sv,
    "Monterrey"sv,
    "Montreal"sv,
    "Moscow"sv,
    "Mumbai"sv,
    "Murmansk"sv,
    "Muscat"sv,
    "Mzuzu"sv,
    "N'Djamena"sv,
    "Naha"sv,
    "Nairobi"sv,
    "Nakhon Ratchasima"sv,
    "Napier"sv,
    "Napoli"sv,
    "Nashville"sv,
    "Nassau"sv,
    "Ndola"sv,
    "New Delhi"sv,
    "New Orleans"sv,
    "New York City"sv,
    "Ngaoundéré"sv,
    "Niamey"sv,
    "Nicosia"sv,
    "Niigata"sv,
    "Nouadhibou"sv,
    "Nouakchott"sv,
    "Novosibirsk"sv,
    "Nuuk"sv,
    "Odesa"sv,
    "Odienné"sv,
    "Oklahoma City"sv,
    "Omaha"sv,
    "Oranjestad"sv,
    "Oslo"sv,
    "Ottawa"sv,
    "Ouagadougou"sv,
    "Ouahigouya"sv,
    "Ouarzazate"sv,
    "Oulu"sv,
    "Palembang"sv,
    "Palermo"sv,
    "Palm Springs"sv,
    "Palmerston North"sv,
    "Panama City"sv,
    "Parakou"sv,
    "Paris"sv,
    "Perth"sv,
    "Petropavlovsk-Kamchatsky"sv,
    "Philadelphia"sv,
    "Phnom Penh"sv,
    "Phoenix"sv,
    "Pittsburgh"sv,
    "Podgorica"sv,
    "Pointe-Noire"sv,
    "Pontianak"sv,
    "Port Moresby"sv,
    "Port Sudan"sv,
    "Port Vila"sv,
    "Port-Gentil"sv,
    "Portland (OR)"sv,
    "Porto"sv,
    "Prague"sv,
    "Praia"sv,
    "Pretoria"sv,
    "Pyongyang"sv,
    "Rabat"sv,
    "Rangpur"sv,
    "Reggane"sv,
    "Reykjavík"sv,
    "Riga"sv,
    "Riyadh"sv,
    "Rome"sv,
    "Roseau"sv,
    "Rostov-on-Don"sv,
    "Sacramento"sv,
    "Saint Petersburg"sv,
    "Saint-Pierre"sv,
    "Salt Lake City"sv,
    "San Antonio"sv,
    "San Diego"sv,
    "San Francisco"sv,
    "San Jose"sv,
    "San José"sv,
    "San Juan"sv,
    "San Salvador"sv,
    "Sana'a"sv,
    "Santo Domingo"sv,
    "Sapporo"sv,
    "Sarajevo"sv,
    "Saskatoon"sv,
    "Seattle"sv,
    "Seoul"sv,
    "Seville"sv,
    "Shanghai"sv,
    "Singapore"sv,
    "Skopje"sv,
    "Sochi"sv,
    "Sofia"sv,
    "Sokoto"sv,
    "Split"sv,
    "St. John's"sv,
    "St. Louis"sv,
    "Stockholm"sv,
    "Surabaya"sv,
    "Suva"sv,
    "Suwałki"sv,
    "Sydney"sv,
    "Ségou"sv,
    "Tabora"sv,
    "Tabriz"sv,
    "Taipei"sv,
    "Tallinn"sv,
    "Tamale"sv,
    "Tamanrasset"sv,
    "Tampa"sv,
    "Tashkent"sv,
    "Tauranga"sv,
    "Tbilisi"sv,
    "Tegucigalpa"sv,
    "Tehran"sv,
    "Tel Aviv"sv,
    "Thessaloniki"sv,
    "Thiès"sv,
    "Tijuana"sv,
    "Timbuktu"sv,
    "Tirana"sv,
    "Toamasina"sv,
    "Tokyo"sv,
    "Toliara"sv,
    "Toluca"sv,
    "Toronto"sv,
    "Tripoli"sv,
    "Tromsø"sv,
    "Tucson"sv,
    "Tunis"sv,
    "Ulaanbaatar"sv,
    "Upington"sv,
    "Vaduz"sv,
    "Valencia"sv,
    "Valletta"sv,
    "Vancouver"sv,
    "Veracruz"sv,
    "Vienna"sv,
    "Vientiane"sv,
    "Villahermosa"sv,
    "Vilnius"sv,
    "Virginia Beach"sv,
    "Vladivostok"sv,
    "Warsaw"sv,
    "Washington, D.C."sv,
    "Wau"sv,
    "Wellington"sv,
    "Whitehorse"sv,
    "Wichita"sv,
    "Willemstad"sv,
    "Winnipeg"sv,
    "Wrocław"sv,
    "Xi'an"sv,
    "Yakutsk"sv,
    "Yangon"sv,
    "Yaoundé"sv,
    "Yellowknife"sv,
    "Yerevan"sv,
    "Yinchuan"sv,
    "Zagreb"sv,
    "Zanzibar City"sv,
    "Zürich"sv,
    "Ürümqi"sv,
    "İzmir"sv,
};

static constexpr uint32_t o1hash(const char *s, size_t len) {
  static_assert(HWY_IS_LITTLE_ENDIAN, "Only support little endian");

  if consteval {
    if (len >= 4) {
      uint32_t first = (std::bit_cast<uint8_t>(s[3]) << 24) +
                       (std::bit_cast<uint8_t>(s[2]) << 16) +
                       (std::bit_cast<uint8_t>(s[1]) << 8) +
                       std::bit_cast<uint8_t>(s[0]),
               last = (std::bit_cast<uint8_t>(s[len - 1]) << 24) +
                      (std::bit_cast<uint8_t>(s[len - 2]) << 16) +
                      (std::bit_cast<uint8_t>(s[len - 3]) << 8) +
                      std::bit_cast<uint8_t>(s[len - 4]);
      return first + last;
    } else if (len) {
      return (std::bit_cast<uint8_t>(s[0]) << 16) |
             std::bit_cast<uint8_t>(s[len - 1]);
    }
  } else {
    if (len >= 4) {
      uint32_t first = *reinterpret_cast<const uint32_t *>(s),
               last = *reinterpret_cast<const uint32_t *>(s + len - 4);
      return first + last;
    } else if (len) {
      return (std::bit_cast<uint8_t>(s[0]) << 16) |
             std::bit_cast<uint8_t>(s[len - 1]);
    }
  }

  return 0;
}

static constexpr auto _table = []() consteval {
  std::array<uint32_t, std::size(_names)> values;
  size_t i = 0;
  for (auto &v : values) {
    auto name = _names[i++];
    // A whole record must fit in one window: name, ';', "-99.9" and '\n'.
    if (name.size() + 7 > kWindow) {
      throw "City name too long";
    }
    v = o1hash(name.data(), name.size());
  }
  return values;
}();

static int city_id(const char *name, size_t len) {
  return mph::lookup<_table>(o1hash(name, len));
}

static std::string_view city_name(int id) { return _names[id]; }

static std::size_t city_count() { return _names.size(); }
