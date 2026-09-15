#!/usr/bin/env python3
import os, sys, json, zoneinfo, datetime, math

CONFIG_PATH = os.path.expanduser('~/.config/omarchy/vibesWorldTime.json')
DEFAULT_CITIES = [
    {"name": "San Francisco", "tz": "America/Los_Angeles"},
    {"name": "New York", "tz": "America/New_York"},
    {"name": "London", "tz": "Europe/London"},
    {"name": "Tokyo", "tz": "Asia/Tokyo"}
]

# Coordinate lookup from zone1970.tab
TZ_COORDS = None

def parse_iso6709(coord):
    try:
        sign2_idx = 0
        for i in range(1, len(coord)):
            if coord[i] in ('+', '-'):
                sign2_idx = i
                break
        lat_str = coord[:sign2_idx]
        lon_str = coord[sign2_idx:]
        def to_dec(s):
            sign = -1 if s[0] == '-' else 1
            s = s[1:]
            if len(s) == 4:
                return sign * (int(s[:2]) + int(s[2:]) / 60.0)
            elif len(s) == 5:
                return sign * (int(s[:3]) + int(s[3:]) / 60.0)
            elif len(s) == 6:
                return sign * (int(s[:2]) + int(s[2:4]) / 60.0 + int(s[4:]) / 3600.0)
            elif len(s) == 7:
                return sign * (int(s[:3]) + int(s[3:5]) / 60.0 + int(s[5:]) / 3600.0)
            return 0.0
        return to_dec(lat_str), to_dec(lon_str)
    except Exception:
        return 0.0, 0.0

def get_tz_coords():
    global TZ_COORDS
    if TZ_COORDS is not None:
        return TZ_COORDS
    coords = {}
    path = '/usr/share/zoneinfo/zone1970.tab'
    if os.path.exists(path):
        try:
            with open(path, 'r', encoding='utf-8') as f:
                for line in f:
                    if line.startswith('#') or not line.strip():
                        continue
                    parts = line.strip().split('\t')
                    if len(parts) >= 3:
                        coords[parts[2]] = parse_iso6709(parts[1])
        except Exception:
            pass
    TZ_COORDS = coords
    return TZ_COORDS

def calc_sun(lat, lon, date, tz):
    try:
        day_of_year = date.timetuple().tm_yday
        gamma = 2 * math.pi / 365 * (day_of_year - 1)
        eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(gamma) - 0.032077 * math.sin(gamma) \
                 - 0.014615 * math.cos(2 * gamma) - 0.040849 * math.sin(2 * gamma))
        decl = 0.006918 - 0.399912 * math.cos(gamma) + 0.070257 * math.sin(gamma) \
               - 0.006758 * math.cos(2 * gamma) + 0.000907 * math.sin(2 * gamma)
        lat_rad = math.radians(lat)
        zenith_rad = math.radians(90.833)
        cos_ha = (math.cos(zenith_rad) / (math.cos(lat_rad) * math.cos(decl))) - (math.tan(lat_rad) * math.tan(decl))
        if cos_ha > 1 or cos_ha < -1:
            return None, None
        ha = math.degrees(math.acos(cos_ha))
        solar_noon_utc = 720 - 4 * lon - eqtime
        sunrise_utc_min = solar_noon_utc - ha * 4
        sunset_utc_min = solar_noon_utc + ha * 4
        utc_midnight = datetime.datetime(date.year, date.month, date.day, tzinfo=datetime.timezone.utc)
        sunrise_dt = (utc_midnight + datetime.timedelta(minutes=sunrise_utc_min)).astimezone(tz)
        sunset_dt = (utc_midnight + datetime.timedelta(minutes=sunset_utc_min)).astimezone(tz)
        return sunrise_dt, sunset_dt
    except Exception:
        return None, None

def load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, 'r', encoding='utf-8') as f:
                data = json.load(f)
                if isinstance(data, dict):
                    return data
        except Exception:
            pass
    return {
        "cities": DEFAULT_CITIES,
        "timeFormat24h": True,
        "showWeekNumbers": False,
        "firstDayOfWeek": "monday", # "monday" or "sunday"
        "showSunriseSunset": True
    }

def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, 'w', encoding='utf-8') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)

def get_clocks():
    cfg = load_config()
    cities = cfg.get("cities", DEFAULT_CITIES)
    is_24h = cfg.get("timeFormat24h", True)
    show_weeks = cfg.get("showWeekNumbers", False)
    first_day = cfg.get("firstDayOfWeek", "monday")
    show_sun = cfg.get("showSunriseSunset", True)
    
    now_utc = datetime.datetime.now(datetime.timezone.utc)
    local_dt = datetime.datetime.now().astimezone()
    coords_map = get_tz_coords()
    
    clocks = []
    for idx, c in enumerate(cities):
        try:
            tz = zoneinfo.ZoneInfo(c["tz"])
            dt = now_utc.astimezone(tz)
        except Exception:
            continue
            
        diff_sec = (dt.utcoffset() - local_dt.utcoffset()).total_seconds()
        diff_hours = diff_sec / 3600.0
        
        # Day relationship relative to local date
        day_diff = (dt.date() - local_dt.date()).days
        if day_diff == 0:
            day_str = "Today"
        elif day_diff == 1:
            day_str = "Tomorrow"
        elif day_diff == -1:
            day_str = "Yesterday"
        elif day_diff > 1:
            day_str = f"+{day_diff} days"
        else:
            day_str = f"{day_diff} days"
            
        # Offset string
        if abs(diff_hours) < 0.05:
            offset_str = "Same time"
        elif diff_hours > 0:
            h = int(diff_hours) if diff_hours.is_integer() else round(diff_hours, 1)
            offset_str = f"{h} hours ahead" if h != 1 else "1 hour ahead"
        else:
            h = abs(int(diff_hours)) if diff_hours.is_integer() else abs(round(diff_hours, 1))
            offset_str = f"{h} hours behind" if h != 1 else "1 hour behind"
            
        # Time format
        if is_24h:
            time_str = dt.strftime("%H:%M")
        else:
            time_str = dt.strftime("%I:%M %p").lstrip("0")
            
        # Business hours status color:
        # Green: 9am - 6pm (09:00 - 18:00)
        # Yellow: up to 8pm (18:00 - 20:00)
        # Red: out of hours (< 09:00 or >= 20:00)
        current_hour = dt.hour + dt.minute / 60.0
        if 9.0 <= current_hour < 18.0:
            status_color = "green"
            status_tip = "Working hours (9am-6pm)"
        elif 18.0 <= current_hour < 20.0:
            status_color = "yellow"
            status_tip = "Evening (until 8pm)"
        else:
            status_color = "red"
            status_tip = "Out of hours"
            
        # Sunrise / Sunset
        sunrise_str = ""
        sunset_str = ""
        if show_sun:
            lat_lon = coords_map.get(c["tz"])
            if lat_lon:
                sr, ss = calc_sun(lat_lon[0], lat_lon[1], dt.date(), tz)
                if sr and ss:
                    if is_24h:
                        sunrise_str = sr.strftime("%H:%M")
                        sunset_str = ss.strftime("%H:%M")
                    else:
                        sunrise_str = sr.strftime("%I:%M%p").lstrip("0").lower()
                        sunset_str = ss.strftime("%I:%M%p").lstrip("0").lower()

        clocks.append({
            "id": idx,
            "name": c["name"],
            "tz": c["tz"],
            "time": time_str,
            "day": day_str,
            "offset": offset_str,
            "diff_hours": diff_hours,
            "status_color": status_color,
            "status_tip": status_tip,
            "sunrise": sunrise_str,
            "sunset": sunset_str
        })
        
    # Default order: oldest time to newest
    clocks.sort(key=lambda x: x["diff_hours"])
    
    return {
        "clocks": clocks,
        "timeFormat24h": is_24h,
        "showWeekNumbers": show_weeks,
        "firstDayOfWeek": first_day,
        "showSunriseSunset": show_sun
    }

def get_searchable_cities():
    tzs = sorted(list(zoneinfo.available_timezones()))
    items = []
    seen = set()
    for tz in tzs:
        if '/' in tz and not tz.startswith(('Etc/', 'SystemV/')):
            parts = tz.split('/')
            city = parts[-1].replace('_', ' ')
            region = parts[0].replace('_', ' ')
            if city not in seen:
                seen.add(city)
                items.append({
                    "name": city,
                    "tz": tz,
                    "display": f"{city}, {region}"
                })
    return items

ALL_CITIES = None

def search_cities(query):
    global ALL_CITIES
    if ALL_CITIES is None:
        ALL_CITIES = get_searchable_cities()
    q = query.lower().strip()
    if not q:
        return []
    matches = []
    for item in ALL_CITIES:
        if q in item["name"].lower() or q in item["tz"].lower():
            matches.append(item)
            if len(matches) >= 15:
                break
    return matches

def main():
    if len(sys.argv) < 2 or sys.argv[1] == "get":
        print(json.dumps(get_clocks()))
        return
        
    cmd = sys.argv[1]
    if cmd == "search":
        q = sys.argv[2] if len(sys.argv) > 2 else ""
        print(json.dumps(search_cities(q)))
    elif cmd == "add":
        if len(sys.argv) >= 4:
            name = sys.argv[2]
            tz = sys.argv[3]
            cfg = load_config()
            cities = cfg.get("cities", DEFAULT_CITIES)
            if not any(c.get("tz") == tz for c in cities):
                cities.append({"name": name, "tz": tz})
                cfg["cities"] = cities
                save_config(cfg)
            print(json.dumps(get_clocks()))
    elif cmd == "delete":
        if len(sys.argv) >= 3:
            name = sys.argv[2]
            cfg = load_config()
            cities = [c for c in cfg.get("cities", DEFAULT_CITIES) if c.get("name") != name]
            cfg["cities"] = cities
            save_config(cfg)
            print(json.dumps(get_clocks()))
    elif cmd == "set_setting":
        if len(sys.argv) >= 4:
            key = sys.argv[2]
            val = sys.argv[3]
            cfg = load_config()
            if val.lower() == "true":
                cfg[key] = True
            elif val.lower() == "false":
                cfg[key] = False
            else:
                cfg[key] = val
            save_config(cfg)
            print(json.dumps(get_clocks()))
    elif cmd == "reset_defaults":
        cfg = load_config()
        cfg["cities"] = DEFAULT_CITIES
        save_config(cfg)
        print(json.dumps(get_clocks()))
    else:
        print(json.dumps(get_clocks()))

if __name__ == '__main__':
    main()
