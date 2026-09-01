"""Interactive Gradio demo for AI-based Adaptive Noise Cancellation."""

from __future__ import annotations

import gradio as gr
import numpy as np

from anc.processor import ANCProcessor
from anc.signals import NOISE_PROFILES
from anc.visualize import (
    plot_ai_parameters,
    plot_metrics_bar,
    plot_spectrograms,
    plot_waveforms,
    to_gradio_audio,
)


processor = ANCProcessor(filter_length=128, block_size=512)


def run_demo(
    noise_profile: str,
    snr_db: float,
    duration: float,
    use_ai: bool,
    fixed_mu: float,
    seed: int,
):
    baseline = processor.process(
        noise_profile=noise_profile,
        snr_db=snr_db,
        duration=duration,
        use_ai=False,
        fixed_mu=fixed_mu,
        seed=seed,
    )
    result = processor.process(
        noise_profile=noise_profile,
        snr_db=snr_db,
        duration=duration,
        use_ai=use_ai,
        fixed_mu=fixed_mu,
        seed=seed,
    )

    mode = "AI-Adaptive NLMS" if use_ai else "Fixed NLMS"
    summary = (
        f"**Noise profile:** {noise_profile}  \n"
        f"**Input SNR:** {snr_db:.1f} dB  \n"
        f"**Mode:** {mode}  \n"
        f"**Noise reduction:** {result.snr_improvement_db:.1f} dB  \n"
        f"**Fixed NLMS baseline:** {baseline.snr_improvement_db:.1f} dB  \n"
        f"**AI advantage:** {result.snr_improvement_db - baseline.snr_improvement_db:+.1f} dB"
    )

    ai_table = []
    if result.ai_history:
        for h in result.ai_history:
            ai_table.append(
                [
                    f"{h['start'] / result.sample_rate:.2f}s",
                    f"{h['end'] / result.sample_rate:.2f}s",
                    f"{h['step_size']:.4f}",
                    f"{h['filter_gain']:.3f}",
                    f"{h['features'][0]:.4f}",
                    f"{h['features'][2]:.3f}",
                ]
            )

    return (
        summary,
        to_gradio_audio(result.primary, result.sample_rate),
        to_gradio_audio(result.output, result.sample_rate),
        to_gradio_audio(result.clean, result.sample_rate),
        plot_waveforms(result),
        plot_spectrograms(result),
        plot_ai_parameters(result),
        plot_metrics_bar(result, baseline.snr_improvement_db),
        ai_table,
    )


def build_app() -> gr.Blocks:
    noise_choices = list(NOISE_PROFILES.keys())

    with gr.Blocks(
        title="AI Adaptive Noise Cancellation Demo",
        theme=gr.themes.Soft(primary_hue="blue"),
    ) as app:
        gr.Markdown(
            """
            # AI-Based Adaptive Noise Cancellation (ANC) Demo

            This demo simulates **feed-forward active noise cancellation** — the same principle
            used in headphones and hearing aids. A reference microphone captures ambient noise,
            an adaptive filter learns the noise path, and subtracts it from the primary signal.

            **What makes it AI-based?** A small neural network analyzes noise characteristics
            (spectral shape, energy, tonality) in real time and dynamically adjusts the NLMS
            filter's step size and gain — converging faster and reducing distortion compared
            to a fixed-parameter filter.
            """
        )

        with gr.Row():
            with gr.Column(scale=1):
                noise_profile = gr.Dropdown(noise_choices, value=noise_choices[0], label="Noise profile")
                snr_db = gr.Slider(0, 15, value=5, step=0.5, label="Input SNR (dB)")
                duration = gr.Slider(1, 5, value=3, step=0.5, label="Duration (seconds)")
                use_ai = gr.Checkbox(value=True, label="Enable AI-adaptive parameters")
                fixed_mu = gr.Slider(0.001, 0.2, value=0.02, step=0.001, label="Fixed NLMS step size (μ)")
                seed = gr.Number(value=42, precision=0, label="Random seed")
                run_btn = gr.Button("Run ANC Demo", variant="primary")

            with gr.Column(scale=2):
                summary = gr.Markdown("Click **Run ANC Demo** to start.")

        with gr.Row():
            audio_noisy = gr.Audio(label="Primary (noisy input)")
            audio_clean = gr.Audio(label="ANC output")
            audio_ref = gr.Audio(label="Clean speech reference")

        with gr.Row():
            wave_plot = gr.Image(label="Waveforms")
            spec_plot = gr.Image(label="Spectrograms")

        with gr.Row():
            ai_plot = gr.Image(label="AI parameter adaptation")
            metrics_plot = gr.Image(label="Performance comparison")

        ai_table = gr.Dataframe(
            headers=["Start", "End", "Step size μ", "Gain", "RMS energy", "Spectral centroid"],
            label="AI controller decisions (per block)",
            value=[],
        )

        gr.Markdown(
            """
            ### How it works

            | Stage | Description |
            |-------|-------------|
            | **1. Signal model** | Clean speech mixed with noise at a configurable SNR |
            | **2. Reference path** | A correlated copy of the noise (simulating a reference mic) |
            | **3. NLMS filter** | 128-tap adaptive FIR filter cancels the noise component |
            | **4. AI controller** | 2-layer MLP maps 8 noise features → optimal μ and gain |
            | **5. Output** | Denoised speech with reduced residual noise |

            Based on the **Normalized Least Mean Squares (NLMS)** algorithm with
            **AI-driven hyperparameter adaptation**.
            """
        )

        run_btn.click(
            fn=run_demo,
            inputs=[noise_profile, snr_db, duration, use_ai, fixed_mu, seed],
            outputs=[
                summary,
                audio_noisy,
                audio_clean,
                audio_ref,
                wave_plot,
                spec_plot,
                ai_plot,
                metrics_plot,
                ai_table,
            ],
        )

    return app


if __name__ == "__main__":
    demo = build_app()
    demo.launch(server_name="0.0.0.0", server_port=7860)
