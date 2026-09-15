#!/usr/bin/env python3
import os, sys, json, zoneinfo, datetime

CONFIG_PATH = os.path.expanduser('~/.config/omarchy/vibesWorldTime.json')
DEFAULT_CITIES = [
    {"name": "San Francisco", "tz": "America/Los_Angeles"},
    {"name": "New York", "tz": "America/New_York"},
    {"name": "London", "tz": "Europe/London"},
    {"name": "Tokyo", "tz": "Asia/Tokyo"}
]

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
        "showWeekNumbers": False
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
    
    now_utc = datetime.datetime.now(datetime.timezone.utc)
    local_dt = datetime.datetime.now().astimezone()
    
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
            
        if is_24h:
            time_str = dt.strftime("%H:%M")
        else:
            # 12-hour without leading zero
            time_str = dt.strftime("%I:%M %p").lstrip("0")
            
        clocks.append({
            "id": idx,
            "name": c["name"],
            "tz": c["tz"],
            "time": time_str,
            "day": day_str,
            "offset": offset_str,
            "diff_hours": diff_hours
        })
        
    # Default order: oldest time to newest (earliest to latest diff_hours)
    clocks.sort(key=lambda x: x["diff_hours"])
    
    return {
        "clocks": clocks,
        "timeFormat24h": is_24h,
        "showWeekNumbers": show_weeks
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
            # Avoid duplicate by tz
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
    elif cmd == "toggle_format":
        cfg = load_config()
        cfg["timeFormat24h"] = not cfg.get("timeFormat24h", True)
        save_config(cfg)
        print(json.dumps(get_clocks()))
    elif cmd == "toggle_weeks":
        cfg = load_config()
        cfg["showWeekNumbers"] = not cfg.get("showWeekNumbers", False)
        save_config(cfg)
        print(json.dumps(get_clocks()))
    else:
        print(json.dumps(get_clocks()))

if __name__ == '__main__':
    main()
