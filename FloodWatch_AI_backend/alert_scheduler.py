
import os
import time
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

from alert_monitor import run_alert_check

INTERVAL_SECONDS = 30 * 60
TIMEZONE = ZoneInfo("Asia/Kolkata")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)


def main():
    logging.info("FloodGuard alert scheduler started.")

    while True:
        try:
            current_time = datetime.now(TIMEZONE)
            logging.info(
                "Running alert check at %s",
                current_time.strftime("%Y-%m-%d %H:%M:%S"),
            )

            result = run_alert_check()
            logging.info("Alert check result: %s", result)

        except Exception:
            logging.exception("Alert check failed.")

        logging.info("Next alert check in 30 minutes.")
        time.sleep(INTERVAL_SECONDS)


if __name__ == "__main__":
    main()

