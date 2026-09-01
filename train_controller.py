"""One-time script to train and save AI controller weights."""

from __future__ import annotations

from pathlib import Path

from anc.ai_controller import MLPController

WEIGHTS_PATH = Path(__file__).parent / "anc" / "model_weights.json"


def main() -> None:
    print("Training AI controller (this may take ~2 minutes)...")
    ctrl = MLPController()
    ctrl.save_weights(WEIGHTS_PATH)
    print(f"Saved weights to {WEIGHTS_PATH}")


if __name__ == "__main__":
    main()
