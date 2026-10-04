"""一鍵準備音效實驗室的試聽檔：下載原始素材（約 3 GB）→ 產生預聽檔（約 220 MB）。

用法：python tools/audio/setup_audition.py [--jobs N]

新機器上第一次使用音效實驗室前跑一次。下載與預聽檔都會略過已存在的，所以中斷後重跑會接著做；
下載有失敗的素材包時照常產生其餘預聽檔，並在最後列出失敗數，重跑即可補上。
"""
import argparse
import subprocess
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent


def run(script: str, *args: str) -> int:
    return subprocess.call([sys.executable, str(TOOLS / script), *args])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--jobs", type=int, default=4, help="同時下載的素材包數")
    args = parser.parse_args()
    print("== 1/2 下載原始素材")
    fetch_status = run("fetch_audio.py", "--jobs", str(args.jobs))
    print("== 2/2 產生預聽檔")
    build_status = run("build_candidates.py")
    if fetch_status or build_status:
        print("有項目失敗，請看上面的 FAIL 訊息；重跑同一個指令會補上。", file=sys.stderr)
    return 1 if fetch_status or build_status else 0


if __name__ == "__main__":
    sys.exit(main())
