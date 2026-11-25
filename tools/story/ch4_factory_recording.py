"""Version 31 at the factory recorder and ward bedside radio."""

from ch1_closure import Option, all_of, flag, grant, negate, say, set_flag
from build_ch1_story import sfx

ARCHIVE_INDEX = "ch4_archive_31_index"
ARCHIVE_RECORDING = "ch4_archive_31_recording"
INDEXED = "ch4_archive_31_indexed"
HEARD = "ch4_archive_31_heard"
OFFICE_OPEN = "ch4_office_access"
WARD_DEMO = "ch4_voice_demo_read"

RECORDING_LINE = "今天也可以重新開始。汐聽得見我的聲音嗎？"


def add_factory_recording(source, dispatch):
    source.speakers["archive_tape"] = {
        "name": "盤帶錄音", "name_ja": "テープ録音", "name_en": "Reel recording",
        "color": "#d5c7a3", "portrait": "res://art/portraits/system.png",
    }
    source.documents[ARCHIVE_INDEX] = {
        "name": "第三十一版登錄卡",
        "icon": "doc_stub",
        "description": "盤帶盒上保留的試錄版號，供日後補聽用。",
        "body": "天穹電話亭標語試錄的版號為 31。舊廠辦公室的盤帶機和雨窗旁的床邊電台都可以播放字幕。",
        "source_actor": "ch4_archive_recorder",
    }
    source.documents[ARCHIVE_RECORDING] = {
        "name": "天穹第三十一版逐字稿",
        "icon": "recording",
        "description": "天穹電話亭的標語試錄收有一段未公開的片尾。",
        "body": RECORDING_LINE,
        "source_actor": "ch4_archive_recorder",
    }

    dispatch["archive_recorder"] = ["ch4_t_archive_menu_office"]
    dispatch["voice_demo"].insert(0, "ch4_t_archive_menu_ward")
    office = flag(OFFICE_OPEN)
    bedside = all_of(flag(INDEXED), flag(WARD_DEMO))
    unheard = negate(flag(HEARD))
    replay = Option(
        "replay", "重播第三十一版的字幕。", "ch4_t_archive_replay", "再次播放原來的片尾。", when=flag(HEARD),
    )
    leave = Option("leave", "先把播放器關上。", None, "之後還可以回來查看。")

    source.add("ch4_t_archive_menu_office", "13", (
        ("lamp", "盤帶盒寫著第三十一版。這卷用來試錄天穹電話亭的標語。"),
    ), when=office, options=(
        Option("index", "只記下盤帶版號。", "ch4_t_archive_index", "日後可以在病房的床邊電台補聽。",
               when=negate(flag(INDEXED))),
        Option("play", "播放第三十一版的字幕。", "ch4_t_archive_play_office", "播完會留存逐字稿。", when=unheard),
        replay,
        leave,
    ), cancel_choice_on_back=True)
    source.add("ch4_t_archive_menu_ward", "13", (
        ("lamp", "這台電台能播放記下的盤帶字幕，也保留護理收音示範。"),
    ), when=bedside, options=(
        Option("play", "播放第三十一版的字幕。", "ch4_t_archive_play_ward", "播完會留存逐字稿。", when=unheard),
        replay,
        Option("demo", "再看原本的收音示範。", "ch4_t_voice_demo_replay", "重看床頭櫃的收音步驟。"),
        leave,
    ), cancel_choice_on_back=True)
    source.add("ch4_t_archive_index", "13", (
        ("rin", "版號已記下。回病房後，還可以用雨窗旁的床邊電台補聽。"),
    ), when=all_of(office, negate(flag(INDEXED))), mode="animated", cancel_on_skip=True,
        completion=(grant(ARCHIVE_INDEX, "archive_recorder"), set_flag(INDEXED)))

    playback = (
        sfx("ch2_radio_static", -20),
        say("archive_tape", RECORDING_LINE),
        say("lamp", "後半句沒有上架。我把它和版號一起留存。"),
        say("rin", "這個名字先只寫在錄音下面。"),
    )
    source.add("ch4_t_archive_play_office", "13", steps=playback,
               when=all_of(office, unheard), mode="animated", cancel_on_skip=True,
               completion=(grant(ARCHIVE_RECORDING, "archive_recorder"), set_flag(INDEXED), set_flag(HEARD)))
    source.add("ch4_t_archive_play_ward", "13", steps=playback,
               when=all_of(bedside, unheard), mode="animated", cancel_on_skip=True,
               completion=(grant(ARCHIVE_RECORDING, "archive_recorder"), set_flag(HEARD)))
    source.add("ch4_t_archive_replay", "13", steps=playback, when=flag(HEARD), mode="animated")
