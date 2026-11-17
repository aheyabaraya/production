#!/usr/bin/env python3
"""Serverless local timeline editor for IDOL edit recipes."""

from __future__ import annotations

import argparse
import copy
import json
import math
import os
import re
import subprocess
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from tkinter import filedialog, messagebox
import tkinter as tk
from tkinter import ttk

import yaml

try:
    from PIL import Image, ImageTk
except ModuleNotFoundError:
    Image = None
    ImageTk = None


REPO_ROOT = Path(__file__).resolve().parents[2]
LEFT_PAD = 118
RIGHT_PAD = 120
TOP_PAD = 28
AXIS_Y = 36
WORK_Y = 58
WORK_H = 22
MARKER_Y = 90
MARKER_H = 28
WAVE_Y = 132
WAVE_H = 58
SECTION_Y = 204
SECTION_H = 34
CLIP_Y = 256
CLIP_H = 46
AUDIO_Y = 316
AUDIO_H = 28
CLIP_GAP = 8
HANDLE_W = 8
MIN_DURATION = 0.08
SNAP_PX = 8
FPS = 24.0
MARKER_COLORS = {
    "cut": "#f0b84f",
    "lyric": "#b59cff",
    "beat": "#65c8d0",
    "section": "#5aa7ff",
    "fix": "#ef6f6c",
    "good_take": "#74c476",
}
UI_BG = "#0f1115"
UI_TOP = "#090a0d"
UI_PANEL = "#161a20"
UI_PANEL_ALT = "#1a1f27"
UI_FIELD = "#0d1015"
UI_VIEWER = "#050607"
UI_BORDER = "#2a313b"
UI_BORDER_SOFT = "#222832"
UI_TEXT = "#e6e9ef"
UI_TEXT_SOFT = "#c2c8d0"
UI_MUTED = "#8e98a8"
UI_MUTED_DARK = "#5d6876"
UI_ACCENT = "#5aa7ff"
UI_ACCENT_DARK = "#17314d"
UI_WARN = "#f0b84f"
UI_DANGER = "#ef6f6c"
UI_HANDLE = "#e8ecf1"


@dataclass
class Hit:
    index: int
    mode: str


class EditDesk:
    def __init__(self, recipe_path: Path | None = None, smoke: bool = False) -> None:
        self.recipe_path: Path | None = None
        self.run_root: Path = REPO_ROOT
        self.payload: dict = {}
        self.undo_stack: list[dict] = []
        self.redo_stack: list[dict] = []
        self.max_history = 120
        self.selected_index: int | None = None
        self.playhead: float = 0.0
        self.scale = 8.0
        self.zoom = 1.0
        self.drag: dict | None = None
        self.waveform: list[float] = []
        self.bpm_summary = ""
        self.bpm_source = ""
        self.song_sections: list[dict] = []
        self.section_source = ""
        self.lyric_marks: list[tuple[float, str]] = []
        self.last_preview_path: Path | None = None
        self.contact_image_ref = None
        self.frame_cache: dict[tuple[str, float, int, int], object] = {}
        self.viewer_image_ref = None
        self.viewer_preview_job = None
        self.is_playing = False
        self.play_job = None
        self.last_play_tick = 0.0
        self.trim_image_refs: list[object] = []
        self.trim_preview_job = None
        self.pending_trim_mode = "selected"
        self.source_duration_cache: dict[str, float] = {}
        self.snapping_enabled = True
        self.resize_job = None
        self.source_tree_paths: dict[str, Path] = {}
        self.source_view_path: Path | None = None
        self.source_view_duration = 0.0
        self.source_view_time = 0.0
        self.source_view_in = 0.0
        self.source_view_out = 0.0
        self.source_image_ref = None
        self.source_preview_job = None
        self.workspace_var = None
        self.tool_mode = "select"
        self.tool_buttons: dict[str, ttk.Button] = {}
        self.console_entry_var = None
        self.job_status_var = None

        if smoke:
            if not recipe_path:
                raise SystemExit("--smoke requires --recipe")
            self.load_recipe(recipe_path)
            print(
                json.dumps(
                    {
                        "recipe": str(self.recipe_path),
                        "run_root": str(self.run_root),
                        "segments": len(self.timeline),
                        "duration": self.total_duration,
                        "audio_path": self.audio_path_text,
                        "song_sections": len(self.song_sections),
                        "bpm": self.bpm_summary,
                    },
                    indent=2,
                )
            )
            return

        self.root = tk.Tk()
        self.root.title("IDOL Edit Desk")
        self.root.geometry("1440x860")
        self.root.minsize(980, 620)
        self.root.configure(bg=UI_BG)
        self._configure_style()
        self._build_ui()
        self.root.bind_all("<Key>", self.on_key_press)
        self.root.bind("<Configure>", self.on_root_configure)

        if recipe_path:
            self.load_recipe(recipe_path)
            self.refresh_all()

    @property
    def timeline(self) -> list[dict]:
        return self.payload.setdefault("timeline", [])

    @property
    def total_duration(self) -> float:
        if not self.timeline:
            return 0.0
        return float(self.timeline[-1].get("output_out", 0.0))

    @property
    def audio_path_text(self) -> str:
        return str(self.payload.get("audio_path", ""))

    @property
    def markers(self) -> list[dict]:
        return self.payload.setdefault("edit_desk_markers", [])

    def _configure_style(self) -> None:
        style = ttk.Style()
        style.theme_use("clam")
        style.configure(".", background=UI_BG, foreground=UI_TEXT, fieldbackground=UI_FIELD)
        style.configure("TFrame", background=UI_BG)
        style.configure("Toolbar.TFrame", background=UI_TOP)
        style.configure("Sidebar.TFrame", background=UI_PANEL)
        style.configure("Header.TFrame", background=UI_TOP)
        style.configure("Panel.TFrame", background=UI_PANEL_ALT)
        style.configure("Monitor.TFrame", background=UI_BG)
        style.configure("TLabel", background=UI_BG, foreground=UI_TEXT)
        style.configure("Muted.TLabel", background=UI_BG, foreground=UI_MUTED)
        style.configure("Title.TLabel", background=UI_TOP, foreground=UI_TEXT, font=("Helvetica", 14, "bold"))
        style.configure("MonitorTitle.TLabel", background=UI_BG, foreground=UI_TEXT_SOFT, font=("Helvetica", 11, "bold"))
        style.configure("PanelTitle.TLabel", background=UI_PANEL, foreground=UI_TEXT_SOFT, font=("Helvetica", 12, "bold"))
        style.configure("Accent.TLabel", background=UI_PANEL, foreground=UI_ACCENT, font=("Helvetica", 10, "bold"))
        style.configure("TButton", background="#20252a", foreground=UI_TEXT, borderwidth=0, padding=(8, 5))
        style.map("TButton", background=[("active", "#2d333d"), ("pressed", UI_ACCENT_DARK)])
        style.configure("Accent.TButton", background=UI_ACCENT_DARK, foreground=UI_TEXT)
        style.map("Accent.TButton", background=[("active", "#214266"), ("pressed", "#254a72")])
        style.configure("Tool.TButton", background=UI_TOP, foreground=UI_TEXT_SOFT, borderwidth=0, padding=(7, 4))
        style.map("Tool.TButton", background=[("active", "#171b22")], foreground=[("active", UI_ACCENT)])
        style.configure("ToolActive.TButton", background=UI_ACCENT_DARK, foreground=UI_TEXT, borderwidth=0, padding=(7, 4))
        style.map("ToolActive.TButton", background=[("active", "#254a72")], foreground=[("active", UI_TEXT)])
        style.configure("TEntry", fieldbackground=UI_FIELD, foreground=UI_TEXT, insertcolor=UI_TEXT, bordercolor=UI_BORDER)
        style.configure("Treeview", background=UI_PANEL_ALT, fieldbackground=UI_PANEL_ALT, foreground=UI_TEXT_SOFT, rowheight=26, bordercolor=UI_BORDER_SOFT)
        style.map("Treeview", background=[("selected", UI_ACCENT_DARK)], foreground=[("selected", UI_TEXT)])
        style.configure("Treeview.Heading", background="#1b2025", foreground=UI_MUTED, relief=tk.FLAT)
        style.configure("TNotebook", background=UI_BG, borderwidth=0)
        style.configure("TNotebook.Tab", background="#1a1e22", foreground=UI_MUTED, padding=(12, 7))
        style.map("TNotebook.Tab", background=[("selected", UI_PANEL_ALT)], foreground=[("selected", UI_TEXT)])
        style.configure("Horizontal.TScale", background=UI_BG, troughcolor=UI_FIELD)

    def _build_ui(self) -> None:
        toolbar = ttk.Frame(self.root, style="Header.TFrame")
        toolbar.pack(fill=tk.X)
        toolbar.grid_columnconfigure(1, weight=1)

        left_tools = ttk.Frame(toolbar, style="Header.TFrame")
        left_tools.grid(row=0, column=0, sticky="w", padx=8, pady=4)
        dots = tk.Canvas(left_tools, width=58, height=18, bg=UI_TOP, highlightthickness=0)
        dots.pack(side=tk.LEFT, padx=(0, 10))
        for idx, color in enumerate(("#ff5f57", "#febc2e", "#28c840")):
            x = 9 + idx * 17
            dots.create_oval(x - 5, 4, x + 5, 14, fill=color, outline="")
        for label, command in [
            ("Open", self.open_recipe),
            ("Video", self.open_video),
            ("Add", self.add_videos),
            ("Save", self.save_draft),
        ]:
            style = "Accent.TButton" if label == "Save" else "Tool.TButton"
            ttk.Button(left_tools, text=label, command=command, style=style).pack(side=tk.LEFT, padx=2)

        ttk.Label(toolbar, text="IDOL Edit Desk", style="Title.TLabel").grid(row=0, column=1)

        right_tools = ttk.Frame(toolbar, style="Header.TFrame")
        right_tools.grid(row=0, column=2, sticky="e", padx=8, pady=4)
        tools = [
            ("Sheet", self.open_contact_sheet),
            ("Lyrics", self.open_lyrics),
            ("BPM", self.load_or_compute_bpm),
            ("Song", self.load_song_waveform),
            ("QC", self.open_preview),
            ("Render", self.render_preview),
            ("Snap", self.save_snapshot),
            ("Undo", self.undo),
            ("Redo", self.redo),
            ("Term", self.open_terminal),
        ]
        for label, command in tools:
            button = ttk.Button(right_tools, text=label, command=command, style="Tool.TButton")
            button.pack(side=tk.LEFT, padx=1)
            if label == "Undo":
                self.undo_button = button
            elif label == "Redo":
                self.redo_button = button

        workspace = ttk.Frame(self.root, style="Header.TFrame")
        workspace.pack(fill=tk.X)
        self.workspace_var = tk.StringVar(value="Edit")
        ttk.Label(workspace, text="Mode", style="Muted.TLabel").pack(side=tk.LEFT, padx=(12, 8), pady=(0, 6))
        for name in ("Edit", "Review", "FX", "Export"):
            button = ttk.Button(workspace, text=name, command=lambda value=name: self.set_workspace(value), style="Tool.TButton")
            button.pack(side=tk.LEFT, padx=2, pady=(0, 6))
            setattr(self, f"workspace_{name.lower()}_button", button)

        self.status_var = tk.StringVar(value="Open a recipe to begin.")
        status = tk.Frame(self.root, bg=UI_BG, highlightthickness=1, highlightbackground=UI_BORDER_SOFT)
        status.pack(fill=tk.X)
        ttk.Label(status, textvariable=self.status_var, style="Muted.TLabel").pack(side=tk.LEFT, fill=tk.X, expand=True, padx=10, pady=(4, 4))
        self.job_status_var = tk.StringVar(value="Jobs: idle")
        ttk.Label(status, textvariable=self.job_status_var, style="Muted.TLabel").pack(side=tk.RIGHT, padx=10, pady=(4, 4))

        main = ttk.PanedWindow(self.root, orient=tk.HORIZONTAL)
        self.main_paned = main
        main.pack(fill=tk.BOTH, expand=True)

        left = ttk.Frame(main, width=310, style="Sidebar.TFrame")
        self.left_panel = left
        main.add(left, weight=0)

        left_tabs = ttk.Frame(left, style="Sidebar.TFrame")
        left_tabs.pack(fill=tk.X, padx=8, pady=(8, 4))
        ttk.Label(left_tabs, text="Runs", style="Accent.TLabel").pack(side=tk.LEFT, padx=(0, 22))
        ttk.Label(left_tabs, text="Recipes", style="Muted.TLabel").pack(side=tk.LEFT)

        self.search_var = tk.StringVar()
        search = ttk.Entry(left, textvariable=self.search_var)
        search.pack(fill=tk.X, padx=8, pady=(4, 8))
        search.insert(0, "Search...")

        ttk.Label(left, text="Clips", style="PanelTitle.TLabel").pack(anchor=tk.W, padx=10, pady=(4, 4))
        self.clip_tree = ttk.Treeview(left, columns=("slot", "start", "dur", "speed"), show="headings", height=12)
        for col, width in [("slot", 132), ("start", 54), ("dur", 54), ("speed", 54)]:
            self.clip_tree.heading(col, text=col)
            anchor = tk.W if col == "slot" else tk.E
            self.clip_tree.column(col, width=width, anchor=anchor)
        self.clip_tree.pack(fill=tk.BOTH, expand=True, padx=8, pady=4)
        self.clip_tree.bind("<<TreeviewSelect>>", self.on_tree_select)

        source_head = ttk.Frame(left, style="Sidebar.TFrame")
        source_head.pack(fill=tk.X, padx=8, pady=(8, 2))
        ttk.Label(source_head, text="Sources", style="PanelTitle.TLabel").pack(side=tk.LEFT)
        ttk.Button(source_head, text="+", command=self.add_videos, style="Tool.TButton").pack(side=tk.RIGHT)
        self.source_tree = ttk.Treeview(left, columns=("status", "meta"), show="tree headings", height=9)
        self.source_tree.heading("#0", text="source")
        self.source_tree.heading("status", text="status")
        self.source_tree.heading("meta", text="meta")
        self.source_tree.column("#0", width=150, anchor=tk.W)
        self.source_tree.column("status", width=64, anchor=tk.W)
        self.source_tree.column("meta", width=58, anchor=tk.E)
        self.source_tree.pack(fill=tk.BOTH, expand=True, padx=8, pady=(0, 8))
        self.source_tree.bind("<Double-1>", self.on_source_tree_double_click)

        center = ttk.Frame(main)
        self.center_panel = center
        main.add(center, weight=1)

        monitors = ttk.Frame(center, style="Monitor.TFrame")
        monitors.pack(fill=tk.X, padx=8, pady=(8, 0))
        monitors.grid_columnconfigure(0, weight=1, minsize=280)
        monitors.grid_columnconfigure(1, weight=2, minsize=480)
        self._build_source_monitor(monitors)
        self._build_program_monitor(monitors)

        section_nav = ttk.Frame(center)
        section_nav.pack(fill=tk.X, padx=0, pady=(0, 1))
        ttk.Button(section_nav, text="← Section", command=self.prev_section).pack(side=tk.LEFT, padx=(4, 3), pady=4)
        ttk.Button(section_nav, text="→ Section", command=self.next_section).pack(side=tk.LEFT, padx=3, pady=4)
        self.section_nav_var = tk.StringVar(value="No section selected")
        ttk.Label(section_nav, textvariable=self.section_nav_var, style="Muted.TLabel").pack(side=tk.LEFT, padx=8)

        timeline_shell = ttk.Frame(center)
        timeline_shell.pack(fill=tk.BOTH, expand=True)
        self._build_timeline_tools(timeline_shell)
        timeline_frame = ttk.Frame(timeline_shell)
        timeline_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.canvas = tk.Canvas(timeline_frame, bg=UI_BG, highlightthickness=0)
        self.canvas.pack(fill=tk.BOTH, expand=True)
        xscroll = ttk.Scrollbar(timeline_frame, orient=tk.HORIZONTAL, command=self.canvas.xview)
        xscroll.pack(fill=tk.X)
        self.canvas.configure(xscrollcommand=xscroll.set)
        self.canvas.bind("<Button-1>", self.on_canvas_down)
        self.canvas.bind("<B1-Motion>", self.on_canvas_drag)
        self.canvas.bind("<ButtonRelease-1>", self.on_canvas_up)
        self.canvas.bind("<MouseWheel>", self.on_mousewheel)
        self.canvas.bind("<Shift-MouseWheel>", self.on_mousewheel)
        self.canvas.bind("<Configure>", lambda _event: self.draw_timeline())

        right = ttk.Frame(main, width=360, style="Sidebar.TFrame")
        self.right_panel = right
        main.add(right, weight=0)
        ttk.Label(right, text="Properties", style="PanelTitle.TLabel").pack(anchor=tk.W, padx=10, pady=(10, 2))
        self.tabs = ttk.Notebook(right)
        self.tabs.pack(fill=tk.BOTH, expand=True, padx=8, pady=(2, 8))
        self._build_inspector_tab()
        self._build_markers_tab()
        self._build_sections_tab()
        self._build_text_tab("Lyrics")
        self._build_contact_tab()
        self._build_console_tab()
        self._build_text_tab("Log")
        self.set_workspace("Edit")
        self.update_tool_buttons()
        self.update_history_buttons()

    def set_workspace(self, name: str) -> None:
        if self.workspace_var is not None:
            self.workspace_var.set(name)
        for workspace in ("Edit", "Review", "FX", "Export"):
            button = getattr(self, f"workspace_{workspace.lower()}_button", None)
            if button is not None:
                button.configure(style="ToolActive.TButton" if workspace == name else "Tool.TButton")
        if name == "Review" and hasattr(self, "contact_tab"):
            self.tabs.select(self.contact_tab)
        elif name == "FX" and hasattr(self, "tabs"):
            self.tabs.select(0)
        elif name == "Export" and hasattr(self, "log_tab"):
            self.tabs.select(self.log_tab)

    def set_tool_mode(self, mode: str) -> None:
        self.tool_mode = mode
        self.update_tool_buttons()
        labels = {
            "select": "Select tool: click clips, move playhead, drag trim handles.",
            "trim": "Trim tool: drag clip edges or use Q/W ripple trim shortcuts.",
            "razor": "Razor tool: click a clip to split at the playhead/click point.",
            "rate": "Rate tool: select a clip and use Speed controls.",
            "hand": "Hand tool: drag the timeline to pan.",
            "marker": "Marker tool: click the timeline to add a cut marker.",
        }
        self.log(labels.get(mode, f"{mode.title()} tool selected."))

    def toggle_snapping(self) -> None:
        self.snapping_enabled = not self.snapping_enabled
        self.log(f"Snapping {'on' if self.snapping_enabled else 'off'}.")
        self.draw_timeline()

    def update_tool_buttons(self) -> None:
        for mode, button in self.tool_buttons.items():
            button.configure(style="ToolActive.TButton" if mode == self.tool_mode else "Tool.TButton")

    def _build_source_monitor(self, parent: ttk.Frame) -> None:
        panel = ttk.Frame(parent, style="Monitor.TFrame")
        panel.grid(row=0, column=0, sticky="nsew", padx=(0, 4))

        head = ttk.Frame(panel)
        head.pack(fill=tk.X)
        ttk.Label(head, text="Source", style="MonitorTitle.TLabel").pack(side=tk.LEFT)
        self.source_title_var = tk.StringVar(value="No source loaded")
        ttk.Label(head, textvariable=self.source_title_var, style="Muted.TLabel").pack(side=tk.LEFT, padx=(10, 0))

        self.source_canvas = tk.Canvas(panel, height=150, bg=UI_VIEWER, highlightthickness=1, highlightbackground=UI_BORDER)
        self.source_canvas.pack(fill=tk.X, pady=(4, 4))
        self.source_canvas.bind("<Configure>", lambda _event: self.queue_source_preview())

        self.source_time_var = tk.StringVar(value="0:00.0 / 0:00.0")
        source_controls = ttk.Frame(panel)
        source_controls.pack(fill=tk.X)
        ttk.Label(source_controls, textvariable=self.source_time_var, style="Muted.TLabel").pack(side=tk.LEFT)

        self.source_scrub_var = tk.DoubleVar(value=0.0)
        self.source_scrub = ttk.Scale(panel, from_=0.0, to=1.0, orient=tk.HORIZONTAL, variable=self.source_scrub_var, command=self.on_source_scrub)
        self.source_scrub.pack(fill=tk.X, pady=(4, 5))

        source_fields = ttk.Frame(panel)
        source_fields.pack(fill=tk.X, pady=(0, 5))
        self.source_in_var = tk.StringVar(value="0.000")
        self.source_out_var = tk.StringVar(value="0.000")
        for label, var in [("In", self.source_in_var), ("Out", self.source_out_var)]:
            frame = ttk.Frame(source_fields)
            frame.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))
            ttk.Label(frame, text=label, width=4, style="Muted.TLabel").pack(side=tk.LEFT)
            ttk.Entry(frame, textvariable=var).pack(side=tk.LEFT, fill=tk.X, expand=True)

        buttons = ttk.Frame(panel)
        buttons.pack(fill=tk.X)
        for label, command in [
            ("Set In", self.set_source_view_in),
            ("Set Out", self.set_source_view_out),
            ("Append", self.append_source_selection),
            ("Fit", self.fit_selected_to_section),
        ]:
            ttk.Button(buttons, text=label, command=command).pack(side=tk.LEFT, padx=(0, 4))

        self.source_status_var = tk.StringVar(value="Double-click a source, or select a clip.")
        ttk.Label(panel, textvariable=self.source_status_var, style="Muted.TLabel").pack(fill=tk.X, pady=(4, 0))

    def _build_program_monitor(self, parent: ttk.Frame) -> None:
        panel = ttk.Frame(parent, style="Monitor.TFrame")
        panel.grid(row=0, column=1, sticky="nsew", padx=(4, 0))

        head = ttk.Frame(panel)
        head.pack(fill=tk.X)
        ttk.Label(head, text="Program", style="MonitorTitle.TLabel").pack(side=tk.LEFT)
        self.viewer_time_var = tk.StringVar(value="0:00.0 / 0:00.0")
        ttk.Label(head, textvariable=self.viewer_time_var, style="Muted.TLabel").pack(side=tk.RIGHT)

        self.viewer_canvas = tk.Canvas(panel, height=330, bg=UI_VIEWER, highlightthickness=1, highlightbackground=UI_BORDER)
        self.viewer_canvas.pack(fill=tk.X, pady=(4, 4))
        self.viewer_canvas.bind("<Configure>", lambda _event: self.queue_viewer_preview())

        viewer_controls = ttk.Frame(panel)
        viewer_controls.pack(fill=tk.X)
        ttk.Button(viewer_controls, text="-1f", command=lambda: self.nudge_playhead(-1.0 / FPS)).pack(side=tk.LEFT, padx=(0, 3))
        ttk.Button(viewer_controls, text="-1s", command=lambda: self.nudge_playhead(-1.0)).pack(side=tk.LEFT, padx=3)
        self.play_button = ttk.Button(viewer_controls, text="Play", command=self.toggle_playback)
        self.play_button.pack(side=tk.LEFT, padx=3)
        ttk.Button(viewer_controls, text="+1s", command=lambda: self.nudge_playhead(1.0)).pack(side=tk.LEFT, padx=3)
        ttk.Button(viewer_controls, text="+1f", command=lambda: self.nudge_playhead(1.0 / FPS)).pack(side=tk.LEFT, padx=3)
        ttk.Button(viewer_controls, text="Render", command=self.render_preview).pack(side=tk.RIGHT)

    def _build_timeline_tools(self, parent: ttk.Frame) -> None:
        strip = ttk.Frame(parent, style="Header.TFrame", width=46)
        strip.pack(side=tk.LEFT, fill=tk.Y)
        ttk.Label(strip, text="Tools", style="Muted.TLabel").pack(padx=4, pady=(8, 4))
        for mode, label in [
            ("select", "V"),
            ("trim", "T"),
            ("razor", "B"),
            ("rate", "R"),
            ("hand", "H"),
            ("marker", "M"),
        ]:
            button = ttk.Button(strip, text=label, command=lambda value=mode: self.set_tool_mode(value), style="Tool.TButton", width=3)
            button.pack(padx=5, pady=2)
            self.tool_buttons[mode] = button
        ttk.Button(strip, text="S", command=self.toggle_snapping, style="Tool.TButton", width=3).pack(padx=5, pady=(12, 2))

    def _build_inspector_tab(self) -> None:
        tab = ttk.Frame(self.tabs)
        self.tabs.add(tab, text="Clip")

        self.inspector_title = tk.StringVar(value="No clip selected")
        ttk.Label(tab, textvariable=self.inspector_title).pack(anchor=tk.W, padx=10, pady=(10, 6))

        self.field_vars: dict[str, tk.StringVar] = {}
        fields = [
            ("source", "Source"),
            ("source_in", "Source In"),
            ("source_out", "Source Out"),
            ("output_duration", "Duration"),
            ("speed", "Speed"),
            ("grade", "Grade"),
        ]
        for key, label in fields:
            frame = ttk.Frame(tab)
            frame.pack(fill=tk.X, padx=10, pady=4)
            ttk.Label(frame, text=label, width=12, style="Muted.TLabel").pack(side=tk.LEFT)
            var = tk.StringVar()
            self.field_vars[key] = var
            ttk.Entry(frame, textvariable=var).pack(side=tk.LEFT, fill=tk.X, expand=True)

        controls = ttk.Frame(tab)
        controls.pack(fill=tk.X, padx=10, pady=8)
        ttk.Button(controls, text="Apply", command=self.apply_fields).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(controls, text="Split", command=self.split_selected).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(controls, text="Delete", command=self.delete_selected).pack(side=tk.LEFT)
        ttk.Button(controls, text="Reveal", command=self.reveal_source).pack(side=tk.LEFT, padx=(6, 0))

        order_controls = ttk.Frame(tab)
        order_controls.pack(fill=tk.X, padx=10, pady=(0, 8))
        ttk.Button(order_controls, text="Move ←", command=lambda: self.move_selected(-1)).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(order_controls, text="Move →", command=lambda: self.move_selected(1)).pack(side=tk.LEFT, padx=(0, 16))
        ttk.Label(order_controls, text="Speed", style="Muted.TLabel").pack(side=tk.LEFT, padx=(0, 6))
        for label, speed in [("0.5x", 0.5), ("1x", 1.0), ("1.5x", 1.5), ("2x", 2.0), ("4x", 4.0)]:
            ttk.Button(order_controls, text=label, command=lambda value=speed: self.set_speed_for_selected(value)).pack(side=tk.LEFT, padx=2)

        speed_frame = ttk.Frame(tab)
        speed_frame.pack(fill=tk.X, padx=10, pady=(0, 8))
        self.speed_slider_var = tk.DoubleVar(value=1.0)
        self.speed_slider_label = tk.StringVar(value="Speed slider: 1.00x")
        ttk.Label(speed_frame, textvariable=self.speed_slider_label, style="Muted.TLabel").pack(anchor=tk.W)
        self.speed_slider = ttk.Scale(speed_frame, from_=0.25, to=4.0, orient=tk.HORIZONTAL, variable=self.speed_slider_var, command=self.on_speed_slider)
        self.speed_slider.pack(fill=tk.X, pady=(3, 0))
        self.speed_slider.bind("<ButtonRelease-1>", lambda _event: self.set_speed_for_selected(self.speed_slider_var.get()))

        fit_frame = ttk.Frame(tab)
        fit_frame.pack(fill=tk.X, padx=10, pady=(0, 8))
        ttk.Button(fit_frame, text="Fit Section", command=self.fit_selected_to_section).pack(side=tk.LEFT)

        ttk.Label(tab, text="Trim Preview", style="Muted.TLabel").pack(anchor=tk.W, padx=10, pady=(8, 4))
        self.trim_canvas = tk.Canvas(tab, height=168, bg=UI_PANEL_ALT, highlightthickness=1, highlightbackground=UI_BORDER_SOFT)
        self.trim_canvas.pack(fill=tk.X, padx=10, pady=(0, 6))
        self.trim_status_var = tk.StringVar(value="Select a clip to show source cut frames.")
        ttk.Label(tab, textvariable=self.trim_status_var, style="Muted.TLabel").pack(anchor=tk.W, padx=10, pady=(0, 8))

        ttk.Label(tab, text="Note", style="Muted.TLabel").pack(anchor=tk.W, padx=10, pady=(12, 4))
        self.note_text = tk.Text(tab, height=8, bg=UI_FIELD, fg=UI_TEXT_SOFT, insertbackground=UI_TEXT, relief=tk.FLAT, wrap=tk.WORD)
        self.note_text.pack(fill=tk.BOTH, expand=True, padx=10, pady=(0, 10))
        ttk.Button(tab, text="Save Note", command=self.apply_note).pack(anchor=tk.E, padx=10, pady=(0, 10))

    def _build_markers_tab(self) -> None:
        tab = ttk.Frame(self.tabs)
        self.markers_tab = tab
        self.tabs.add(tab, text="Markers")

        controls = ttk.Frame(tab)
        controls.pack(fill=tk.X, padx=8, pady=(10, 6))
        self.marker_type_var = tk.StringVar(value="cut")
        self.marker_label_var = tk.StringVar()
        ttk.Combobox(controls, textvariable=self.marker_type_var, values=list(MARKER_COLORS.keys()), width=10, state="readonly").pack(side=tk.LEFT, padx=(0, 6))
        ttk.Entry(controls, textvariable=self.marker_label_var).pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))
        ttk.Button(controls, text="Add", command=self.add_marker_from_panel).pack(side=tk.LEFT)

        self.markers_tree = ttk.Treeview(tab, columns=("time", "type", "label"), show="headings", height=12)
        for col, width in [("time", 70), ("type", 72), ("label", 190)]:
            self.markers_tree.heading(col, text=col)
            self.markers_tree.column(col, width=width, anchor=tk.W)
        self.markers_tree.pack(fill=tk.BOTH, expand=True, padx=8, pady=(0, 8))
        self.markers_tree.bind("<<TreeviewSelect>>", self.on_marker_select)
        self.markers_tree.bind("<Double-1>", lambda _event: self.jump_to_selected_marker())

        actions = ttk.Frame(tab)
        actions.pack(fill=tk.X, padx=8, pady=(0, 8))
        ttk.Button(actions, text="Jump", command=self.jump_to_selected_marker).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(actions, text="Delete", command=self.delete_selected_marker).pack(side=tk.LEFT, padx=(0, 6))
        ttk.Button(actions, text="Generate Cues", command=self.generate_cue_markers).pack(side=tk.LEFT)

    def _build_sections_tab(self) -> None:
        tab = ttk.Frame(self.tabs)
        self.sections_tab = tab
        self.tabs.add(tab, text="Sections")

        self.bpm_var = tk.StringVar(value="BPM: not loaded")
        ttk.Label(tab, textvariable=self.bpm_var, style="Muted.TLabel").pack(anchor=tk.W, padx=10, pady=(10, 6))

        self.sections_tree = ttk.Treeview(tab, columns=("section", "time", "name"), show="headings", height=12)
        for col, width in [("section", 62), ("time", 86), ("name", 190)]:
            self.sections_tree.heading(col, text=col)
            self.sections_tree.column(col, width=width, anchor=tk.W)
        self.sections_tree.pack(fill=tk.X, padx=8, pady=(0, 8))
        self.sections_tree.bind("<<TreeviewSelect>>", self.on_section_select)

        ttk.Label(tab, text="Section Detail", style="Muted.TLabel").pack(anchor=tk.W, padx=10, pady=(4, 4))
        self.section_detail_text = tk.Text(tab, height=10, bg=UI_FIELD, fg=UI_TEXT_SOFT, insertbackground=UI_TEXT, relief=tk.FLAT, wrap=tk.WORD)
        self.section_detail_text.pack(fill=tk.BOTH, expand=True, padx=8, pady=(0, 8))

    def _build_text_tab(self, label: str) -> None:
        tab = ttk.Frame(self.tabs)
        self.tabs.add(tab, text=label)
        text = tk.Text(tab, bg=UI_FIELD, fg=UI_TEXT_SOFT, insertbackground=UI_TEXT, relief=tk.FLAT, wrap=tk.WORD)
        text.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)
        if label == "Lyrics":
            self.lyrics_tab = tab
            self.lyrics_text = text
        else:
            self.log_tab = tab
            self.log_text = text

    def _build_contact_tab(self) -> None:
        tab = ttk.Frame(self.tabs)
        self.contact_tab = tab
        self.tabs.add(tab, text="Review")
        self.contact_canvas = tk.Canvas(tab, bg=UI_PANEL_ALT, highlightthickness=0)
        self.contact_canvas.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

    def _build_console_tab(self) -> None:
        tab = ttk.Frame(self.tabs)
        self.console_tab = tab
        self.tabs.add(tab, text="Console")

        intro = (
            "Local commands: split, marker, render, save, speed 1.25x, trim in +0.20."
        )
        ttk.Label(tab, text=intro, style="Muted.TLabel", wraplength=320).pack(anchor=tk.W, padx=8, pady=(10, 6))

        self.console_text = tk.Text(tab, height=12, bg=UI_FIELD, fg=UI_TEXT_SOFT, insertbackground=UI_TEXT, relief=tk.FLAT, wrap=tk.WORD)
        self.console_text.pack(fill=tk.BOTH, expand=True, padx=8, pady=(0, 8))

        entry_row = ttk.Frame(tab)
        entry_row.pack(fill=tk.X, padx=8, pady=(0, 8))
        self.console_entry_var = tk.StringVar()
        entry = ttk.Entry(entry_row, textvariable=self.console_entry_var)
        entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 6))
        entry.bind("<Return>", lambda _event: self.run_console_command())
        ttk.Button(entry_row, text="Apply", command=self.run_console_command).pack(side=tk.LEFT)
        ttk.Button(entry_row, text="Term", command=self.open_terminal).pack(side=tk.LEFT, padx=(6, 0))

    def set_job_status(self, text: str = "idle") -> None:
        if self.job_status_var is not None:
            self.job_status_var.set(f"Jobs: {self.compact_text(text, 32)}")

    def compact_text(self, text: str, limit: int = 80) -> str:
        value = str(text)
        if len(value) <= limit:
            return value
        if limit <= 3:
            return value[:limit]
        return f"{value[: max(1, limit - 1)]}…"

    def log(self, message: str) -> None:
        stamp = datetime.now().strftime("%H:%M:%S")
        if hasattr(self, "log_text"):
            self.log_text.insert(tk.END, f"[{stamp}] {message}\n")
            self.log_text.see(tk.END)
        if hasattr(self, "console_text"):
            self.console_text.insert(tk.END, f"[{stamp}] {message}\n")
            self.console_text.see(tk.END)
        self.status_var.set(self.compact_text(message, 140))

    def run_console_command(self) -> None:
        if self.console_entry_var is None:
            return
        command = self.console_entry_var.get().strip()
        if not command:
            return
        self.console_entry_var.set("")
        self.log(f"> {command}")
        self.execute_console_command(command)

    def execute_console_command(self, command: str) -> None:
        text = command.strip()
        lowered = text.lower()

        if lowered in {"save", "save draft", "저장", "드래프트 저장"}:
            self.save_draft()
            return
        if lowered in {"snapshot", "스냅샷"}:
            self.save_snapshot()
            return
        if lowered in {"render", "render selected", "preview", "선택 렌더", "선택 구간 렌더"}:
            self.render_preview()
            return
        if lowered in {"split", "split here", "cut", "여기서 자르기", "자르기"}:
            self.split_selected()
            return
        if lowered in {"delete", "delete selected", "삭제", "선택 삭제"}:
            self.delete_selected()
            return
        if lowered in {"marker", "mark", "add marker", "마커", "마커 추가"}:
            self.add_marker_at_playhead("cut")
            return
        if lowered in {"fit", "fit section", "fit to section", "섹션 맞춤"}:
            self.fit_selected_to_section()
            return

        speed_match = re.search(r"(?:speed|속도)\s*(?:selected\s*)?([0-9]+(?:\.[0-9]+)?)\s*x?", lowered)
        if speed_match:
            self.set_speed_for_selected(float(speed_match.group(1)))
            return

        trim_match = re.search(r"trim\s+(?:selected\s+)?(in|out|start|end)\s*([+-]?[0-9]+(?:\.[0-9]+)?)", lowered)
        if trim_match:
            edge = "in" if trim_match.group(1) in {"in", "start"} else "out"
            self.adjust_selected_trim(edge, float(trim_match.group(2)))
            return

        korean_amount = self.first_number(text)
        if korean_amount is not None:
            if "앞" in text and "줄" in text:
                self.adjust_selected_trim("in", korean_amount)
                return
            if "앞" in text and ("늘" in text or "연장" in text):
                self.adjust_selected_trim("in", -korean_amount)
                return
            if "뒤" in text and "줄" in text:
                self.adjust_selected_trim("out", -korean_amount)
                return
            if "뒤" in text and ("늘" in text or "연장" in text):
                self.adjust_selected_trim("out", korean_amount)
                return

        tool_match = re.search(r"(?:tool|툴)\s*(select|trim|razor|rate|hand|marker|선택|트림|자르기|핸드|마커)", lowered)
        if tool_match:
            aliases = {
                "선택": "select",
                "트림": "trim",
                "자르기": "razor",
                "핸드": "hand",
                "마커": "marker",
            }
            self.set_tool_mode(aliases.get(tool_match.group(1), tool_match.group(1)))
            return

        self.log("Console did not apply anything. Use a concrete command, or keep this as a note.")

    def first_number(self, text: str) -> float | None:
        match = re.search(r"([0-9]+(?:\.[0-9]+)?)", text)
        if not match:
            return None
        return float(match.group(1))

    def adjust_selected_trim(self, edge: str, delta_seconds: float) -> None:
        idx = self.selected_index
        if idx is None or idx >= len(self.timeline):
            self.log("Select a clip before trimming.")
            return
        row = self.timeline[idx]
        source_in = float(row.get("source_in", 0.0))
        source_out = float(row.get("source_out", source_in))
        output_duration = max(MIN_DURATION, float(row.get("output_duration", source_out - source_in)))
        source_duration = max(MIN_DURATION, source_out - source_in)
        speed = source_duration / output_duration
        max_source_duration = self.source_duration_for_row(row)

        new_source_in = source_in
        new_source_out = source_out
        new_output_duration = output_duration
        if edge == "in":
            new_source_in = source_in + delta_seconds * speed
            new_output_duration = output_duration - delta_seconds
            if new_source_in < 0:
                new_source_in = 0.0
                new_output_duration = (source_out - new_source_in) / speed
        else:
            new_source_out = source_out + delta_seconds * speed
            new_output_duration = output_duration + delta_seconds
            if max_source_duration > 0 and new_source_out > max_source_duration:
                new_source_out = max_source_duration
                new_output_duration = (new_source_out - source_in) / speed

        if new_output_duration < MIN_DURATION or new_source_out - new_source_in < MIN_DURATION:
            self.log("Trim ignored: clip would become too short.")
            return

        self.push_undo()
        row["source_in"] = round(new_source_in, 6)
        row["source_out"] = round(new_source_out, 6)
        row["output_duration"] = round(new_output_duration, 6)
        self.recalculate_timeline()
        self.playhead = float(row.get("output_in", self.playhead))
        self.refresh_all()
        direction = "start" if edge == "in" else "end"
        self.log(f"Console trim {direction}: {delta_seconds:+.2f}s")

    def open_recipe(self) -> None:
        path = filedialog.askopenfilename(
            title="Open IDOL recipe YAML",
            initialdir=str(REPO_ROOT),
            filetypes=[("YAML", "*.yaml *.yml"), ("All files", "*.*")],
        )
        if path:
            self.load_recipe(Path(path))
            self.refresh_all()

    def open_video(self) -> None:
        path = filedialog.askopenfilename(
            title="Open source video",
            initialdir=str(self.run_root if self.run_root.exists() else REPO_ROOT),
            filetypes=[("Video", "*.mp4 *.mov *.m4v *.mkv *.webm"), ("All files", "*.*")],
        )
        if not path:
            return
        self.load_single_video(Path(path))
        self.refresh_all()

    def add_videos(self) -> None:
        paths = filedialog.askopenfilenames(
            title="Add source videos to timeline",
            initialdir=str(self.run_root if self.run_root.exists() else REPO_ROOT),
            filetypes=[("Video", "*.mp4 *.mov *.m4v *.mkv *.webm"), ("All files", "*.*")],
        )
        if not paths:
            return
        added = self.add_video_paths([Path(path) for path in paths])
        if added:
            self.refresh_all()

    def load_single_video(self, path: Path) -> None:
        path = self.normalize_media_path(path)
        duration = self.source_duration_for_path(path)
        if duration <= 0:
            messagebox.showerror("Open Video", "Could not read the video duration.")
            return

        import_dir = REPO_ROOT / "tools/idol-edit-desk/imports"
        import_dir.mkdir(parents=True, exist_ok=True)
        safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", path.stem).strip("-") or "source-video"
        recipe_path = import_dir / f"{safe_stem}.single-video-recipe.yaml"
        self.recipe_path = recipe_path
        self.run_root = self.infer_run_root(path)
        if self.run_root == REPO_ROOT:
            self.run_root = import_dir
        clip = self.build_video_clip(path, duration, note="Imported with IDOL Edit Desk Open Video.")
        self.payload = {
            "schema_version": "idol_edit_desk.single_video.v1",
            "content_id": safe_stem,
            "status": "single_video_edit_draft",
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "sections": [],
            "timeline": [clip],
        }
        self.recalculate_timeline()
        self.refresh_auto_video_sections()
        self.bpm_summary = ""
        self.bpm_source = ""
        self.selected_index = 0
        self.playhead = 0.0
        if hasattr(self, "root"):
            self.stop_playback()
        self.undo_stack.clear()
        self.redo_stack.clear()
        recipe_path.write_text(yaml.safe_dump(self.payload, allow_unicode=True, sort_keys=False))
        if hasattr(self, "root"):
            self.log(f"Video opened: {path.name} ({duration:.2f}s)")

    def add_video_paths(self, paths: list[Path]) -> int:
        clips: list[dict] = []
        skipped: list[str] = []
        for raw_path in paths:
            path = self.normalize_media_path(raw_path)
            duration = self.source_duration_for_path(path)
            if duration <= 0:
                skipped.append(path.name)
                continue
            clips.append(self.build_video_clip(path, duration, note="Added with IDOL Edit Desk Add Video."))

        if not clips:
            if hasattr(self, "root"):
                messagebox.showerror("Add Video", "Could not read any selected video durations.")
            return 0

        self.ensure_unique_clip_slots(clips)
        had_timeline = bool(self.timeline)
        if had_timeline:
            self.push_undo()
        else:
            first_path = self.normalize_media_path(paths[0])
            self.start_multi_video_session(first_path)

        insert_at = len(self.timeline)
        self.timeline.extend(clips)
        self.recalculate_timeline()
        self.refresh_auto_video_sections()
        self.selected_index = insert_at
        self.playhead = float(self.timeline[insert_at].get("output_in", 0.0))
        self.redo_stack.clear()

        if not had_timeline and self.recipe_path:
            self.recipe_path.write_text(yaml.safe_dump(self.payload, allow_unicode=True, sort_keys=False))

        if hasattr(self, "root"):
            message = f"Added {len(clips)} video clip{'s' if len(clips) != 1 else ''}."
            if skipped:
                message += f" Skipped: {', '.join(skipped[:3])}"
            self.log(message)
        return len(clips)

    def start_multi_video_session(self, first_path: Path) -> None:
        import_dir = REPO_ROOT / "tools/idol-edit-desk/imports"
        import_dir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", first_path.stem).strip("-") or "source-video"
        self.recipe_path = import_dir / f"{safe_stem}-{stamp}.multi-video-recipe.yaml"
        self.run_root = self.infer_run_root(first_path)
        if self.run_root == REPO_ROOT:
            self.run_root = import_dir
        self.payload = {
            "schema_version": "idol_edit_desk.multi_video.v1",
            "content_id": f"{safe_stem}-multi",
            "status": "multi_video_edit_draft",
            "created_at": datetime.now().isoformat(timespec="seconds"),
            "sections": [],
            "timeline": [],
        }
        self.song_sections = []
        self.section_source = ""
        self.bpm_summary = ""
        self.bpm_source = ""
        self.undo_stack.clear()
        self.redo_stack.clear()
        if hasattr(self, "root"):
            self.stop_playback()

    def ensure_unique_clip_slots(self, clips: list[dict]) -> None:
        existing = {str(row.get("slot", "")) for row in self.timeline}
        for clip in clips:
            base = str(clip.get("slot", "clip")).strip() or "clip"
            slot = base
            suffix = 2
            while slot in existing:
                slot = f"{base}_{suffix:02d}"
                suffix += 1
            clip["slot"] = slot
            existing.add(slot)

    def build_video_clip(self, path: Path, duration: float, note: str = "") -> dict:
        safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "-", path.stem).strip("-") or "source-video"
        duplicate_count = sum(1 for row in self.timeline if str(row.get("slot", "")).startswith(safe_stem))
        slot = safe_stem if duplicate_count == 0 else f"{safe_stem}_{duplicate_count + 1:02d}"
        return {
            "slot": slot,
            "source": str(path),
            "source_in": 0.0,
            "source_out": round(duration, 6),
            "output_duration": round(duration, 6),
            "note": note,
        }

    def normalize_media_path(self, path: Path) -> Path:
        path = path.expanduser()
        if not path.is_absolute():
            path = (REPO_ROOT / path).resolve()
        return path

    def refresh_auto_video_sections(self) -> None:
        if self.total_duration <= 0:
            return
        if self.song_sections and self.section_source not in ("", "auto_video_sections") and not self.sections_are_auto(self.song_sections):
            return
        self.payload["sections"] = self.default_video_sections(self.total_duration)
        self.song_sections = self.extract_sections_from_payload(self.payload, "auto_video_sections")
        self.section_source = "auto_video_sections"

    def sections_are_auto(self, sections: list[dict]) -> bool:
        if not sections:
            return False
        return all(str(section.get("function", "")).startswith("Auto video navigation chunk") for section in sections)

    def default_video_sections(self, duration: float) -> list[dict]:
        step = 10.0 if duration > 30 else 5.0
        sections = []
        cursor = 0.0
        idx = 1
        while cursor < duration - 0.001:
            end = min(duration, cursor + step)
            sections.append(
                {
                    "id": f"V{idx:02d}",
                    "name": f"video {cursor:.0f}-{end:.0f}s",
                    "approx_time": f"{cursor:.3f}-{end:.3f}s",
                    "function": "Auto video navigation chunk.",
                }
            )
            cursor = end
            idx += 1
        return sections

    def probe_video_duration(self, path: Path) -> float:
        try:
            proc = subprocess.run(
                [
                    "ffprobe",
                    "-v",
                    "error",
                    "-show_entries",
                    "format=duration",
                    "-of",
                    "json",
                    str(path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            payload = json.loads(proc.stdout or "{}")
            duration = float(payload.get("format", {}).get("duration") or 0)
            if duration > 0:
                return duration
        except Exception:
            pass

        try:
            import cv2

            cap = cv2.VideoCapture(str(path))
            if not cap.isOpened():
                return 0.0
            fps = cap.get(cv2.CAP_PROP_FPS) or 0.0
            frames = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0.0
            cap.release()
            if fps > 0 and frames > 0:
                return float(frames / fps)
        except Exception:
            return 0.0
        return 0.0

    def source_duration_for_path(self, path: Path) -> float:
        path = self.normalize_media_path(path)
        key = str(path)
        if key not in self.source_duration_cache:
            if not path.exists() or not path.is_file():
                self.source_duration_cache[key] = 0.0
            else:
                self.source_duration_cache[key] = max(0.0, self.probe_video_duration(path))
        return self.source_duration_cache[key]

    def source_duration_for_row(self, row: dict) -> float:
        source = self.resolve_source_path(row.get("source", ""))
        return self.source_duration_for_path(source)

    def load_recipe(self, path: Path) -> None:
        path = path.expanduser()
        if not path.is_absolute():
            path = (REPO_ROOT / path).resolve()
        self.recipe_path = path
        self.payload = yaml.safe_load(path.read_text()) or {}
        if "timeline" not in self.payload or not isinstance(self.payload["timeline"], list):
            raise SystemExit(f"No timeline array in {path}")
        if hasattr(self, "root"):
            self.stop_playback()
        self.run_root = self.infer_run_root(path)
        self.recalculate_timeline()
        self.normalize_markers()
        self.song_sections = self.find_song_sections()
        if self.sections_are_auto(self.song_sections):
            self.section_source = "auto_video_sections"
        self.bpm_summary = self.find_bpm_summary()
        self.selected_index = 0 if self.timeline else None
        self.undo_stack.clear()
        self.redo_stack.clear()
        if hasattr(self, "root"):
            self.log(f"Loaded recipe with {len(self.timeline)} clips.")

    def infer_run_root(self, path: Path) -> Path:
        parts = path.resolve().parts
        if "runs" in parts:
            idx = parts.index("runs")
            if len(parts) > idx + 2:
                return Path(*parts[: idx + 3])
        import_dir = REPO_ROOT / "tools/idol-edit-desk/imports"
        try:
            path.resolve().relative_to(import_dir.resolve())
            return import_dir
        except ValueError:
            pass
        return REPO_ROOT

    def recalculate_timeline(self) -> None:
        cursor = 0.0
        for row in self.timeline:
            source_in = max(0.0, float(row.get("source_in", 0.0)))
            source_out = max(source_in, float(row.get("source_out", source_in)))
            max_source_duration = self.source_duration_for_row(row)
            if max_source_duration > 0:
                source_in = min(source_in, max(0.0, max_source_duration - MIN_DURATION))
                source_out = min(max_source_duration, max(source_in + MIN_DURATION, source_out))
                row["source_in"] = round(source_in, 6)
                row["source_out"] = round(source_out, 6)
            output_duration = max(MIN_DURATION, float(row.get("output_duration", source_out - source_in)))
            source_duration = max(0.0, source_out - source_in)
            row["source_duration"] = round(source_duration, 6)
            row["output_in"] = round(cursor, 6)
            row["output_duration"] = round(output_duration, 6)
            cursor += output_duration
            row["output_out"] = round(cursor, 6)
            row["speed_factor"] = round(source_duration / output_duration, 6) if output_duration else 1.0

    def refresh_all(self) -> None:
        self.refresh_tree()
        self.refresh_source_tree()
        self.refresh_inspector()
        self.refresh_sections_table()
        self.refresh_markers_table()
        self.refresh_source_viewer()
        self.draw_timeline()
        self.update_section_nav_label()
        self.update_history_buttons()
        self.status_var.set(self.recipe_path.name if self.recipe_path else "No recipe")

    def refresh_tree(self) -> None:
        self.clip_tree.delete(*self.clip_tree.get_children())
        for idx, row in enumerate(self.timeline):
            speed = float(row.get("speed_factor", 1.0))
            label = row.get("slot") or f"clip-{idx + 1}"
            item = self.clip_tree.insert(
                "",
                tk.END,
                iid=str(idx),
                text=label,
                values=(
                    f"{label}",
                    f"{float(row.get('output_in', 0.0)):.2f}",
                    f"{float(row.get('output_duration', 0.0)):.2f}",
                    f"{speed:.2f}x",
                ),
            )
            self.clip_tree.item(item, text=label)
        if self.selected_index is not None and str(self.selected_index) in self.clip_tree.get_children():
            self.clip_tree.selection_set(str(self.selected_index))

    def refresh_source_tree(self) -> None:
        if not hasattr(self, "source_tree"):
            return
        self.source_tree.delete(*self.source_tree.get_children())
        self.source_tree_paths = {}
        groups: dict[str, list[tuple[Path, float]]] = {}
        for row in self.timeline:
            source = self.resolve_source_path(row.get("source", ""))
            folder = self.short_path(source.parent)
            duration = float(row.get("source_duration", row.get("output_duration", 0.0)))
            groups.setdefault(folder, []).append((source, duration))
        for folder, items in sorted(groups.items()):
            parent = self.source_tree.insert("", tk.END, text=folder, values=(f"{len(items)} items", "folder"), open=True)
            for source, duration in items:
                iid = f"src_{len(self.source_tree_paths)}"
                self.source_tree_paths[iid] = source
                status, meta = self.source_health_for_path(source, duration)
                self.source_tree.insert(parent, tk.END, iid=iid, text=self.compact_text(source.name, 28), values=(status, meta))

    def source_health_for_path(self, source: Path, duration: float) -> tuple[str, str]:
        if not source.exists():
            return "missing", "relink"
        suffix = source.suffix.lower().lstrip(".") or "media"
        native_exts = {"mov", "mp4", "m4v"}
        backend = "native" if suffix in native_exts else "ffmpeg"
        readable_duration = duration
        if readable_duration <= 0:
            readable_duration = self.source_duration_for_path(source)
        duration_text = f"{readable_duration:.1f}s" if readable_duration > 0 else "unknown"
        return backend, f"{duration_text} {suffix}"

    def refresh_inspector(self) -> None:
        idx = self.selected_index
        if idx is None or idx >= len(self.timeline):
            self.inspector_title.set("No clip selected")
            for var in self.field_vars.values():
                var.set("")
            self.note_text.delete("1.0", tk.END)
            self.queue_trim_preview()
            return
        row = self.timeline[idx]
        self.inspector_title.set(str(row.get("slot", f"clip-{idx + 1}")))
        source_duration = max(MIN_DURATION, float(row.get("source_out", 0.0)) - float(row.get("source_in", 0.0)))
        output_duration = max(MIN_DURATION, float(row.get("output_duration", source_duration)))
        speed = source_duration / output_duration
        values = {
            "source": str(row.get("source", "")),
            "source_in": f"{float(row.get('source_in', 0.0)):.6f}",
            "source_out": f"{float(row.get('source_out', 0.0)):.6f}",
            "output_duration": f"{output_duration:.6f}",
            "speed": f"{speed:.4f}",
            "grade": str(row.get("grade", "")),
        }
        for key, value in values.items():
            self.field_vars[key].set(value)
        if hasattr(self, "speed_slider_var"):
            self.speed_slider_var.set(max(0.25, min(4.0, speed)))
            self.speed_slider_label.set(f"Speed slider: {speed:.2f}x")
        self.note_text.delete("1.0", tk.END)
        self.note_text.insert("1.0", str(row.get("note", "")))
        row_source = self.resolve_source_path(row.get("source", ""))
        if (
            self.source_view_path != row_source
            or abs(self.source_view_in - float(row.get("source_in", 0.0))) > 0.001
            or abs(self.source_view_out - float(row.get("source_out", 0.0))) > 0.001
        ):
            self.load_source_from_row(row, select_tab=False)
        self.queue_trim_preview()

    def on_source_tree_double_click(self, _event=None) -> None:
        if not hasattr(self, "source_tree"):
            return
        sel = self.source_tree.selection()
        if not sel:
            return
        path = self.source_tree_paths.get(sel[0])
        if not path:
            return
        self.load_source_view(path)
        self.set_workspace("Edit")

    def run_document_candidates(self) -> list[Path]:
        candidates: list[Path] = []
        if self.recipe_path:
            for name in ("song-sections.yaml", "section-map.yaml", "sections.yaml", "audio-beat-onset-summary.json"):
                candidates.append(self.recipe_path.parent / name)
        if self.run_root and self.run_root != REPO_ROOT:
            research = self.run_root / "research"
            candidates.append(self.run_root / "00A-song-lock.yaml")
            if research.exists():
                candidates.extend(sorted(research.glob("selected-audio-analysis-v*.yaml"), reverse=True))
                candidates.extend(sorted(research.glob("selected-audio-analysis-v*.json"), reverse=True))
                candidates.extend(sorted(research.glob("audio-analysis-v*.json"), reverse=True))
            candidates.append(self.run_root / "00-creative-nucleus.yaml")

        seen: set[Path] = set()
        result: list[Path] = []
        for path in candidates:
            resolved = path.resolve()
            if resolved in seen or not path.exists():
                continue
            seen.add(resolved)
            result.append(path)
        return result

    def find_song_sections(self) -> list[dict]:
        self.section_source = ""
        sections = self.extract_sections_from_payload(self.payload, "recipe")
        if sections:
            self.section_source = "recipe"
            return sections
        for path in self.run_document_candidates():
            try:
                payload = yaml.safe_load(path.read_text()) or {}
            except Exception:
                continue
            sections = self.extract_sections_from_payload(payload, str(path))
            if sections:
                self.section_source = str(path)
                return sections
        return []

    def load_song_sections(self) -> None:
        self.song_sections = self.find_song_sections()
        self.refresh_sections_table()
        self.draw_timeline()
        if self.song_sections:
            self.tabs.select(self.sections_tab)
            source = self.short_path(self.section_source) if self.section_source else "run docs"
            self.log(f"Song sections loaded: {len(self.song_sections)} from {source}")
        else:
            messagebox.showinfo("Sections", "No song section map was found in this recipe or run folder.")

    def extract_sections_from_payload(self, payload: dict, source: str) -> list[dict]:
        section_lists = [
            payload.get("section_interpretation"),
            payload.get("section_map"),
            payload.get("sections"),
        ]
        song_structure = payload.get("song_structure") if isinstance(payload.get("song_structure"), dict) else {}
        section_lists.append(song_structure.get("sections"))

        for entries in section_lists:
            if not isinstance(entries, list):
                continue
            sections = []
            for entry in entries:
                section = self.normalize_section_entry(entry, source)
                if section:
                    sections.append(section)
            if sections:
                sections.sort(key=lambda row: row["start"])
                return sections
        return []

    def normalize_section_entry(self, entry: dict, source: str) -> dict | None:
        if not isinstance(entry, dict):
            return None
        time_text = (
            entry.get("time_range")
            or entry.get("approx_window")
            or entry.get("approx_time")
            or entry.get("timeline")
            or ""
        )
        time_range = self.parse_time_range(time_text)
        if not time_range:
            return None
        start, end = time_range
        raw_name = str(entry.get("section") or entry.get("name") or entry.get("section_name") or "")
        raw_id = str(entry.get("id") or entry.get("section_id") or "")
        id_match = re.search(r"S\d{2}", f"{raw_id} {raw_name} {time_text}")
        section_id = id_match.group(0) if id_match else raw_id
        label = raw_name.replace("_", " ").strip()
        if section_id and label.startswith(section_id):
            label = label[len(section_id) :].strip(" -_:")

        seed = entry.get("lyric_function_seed") if isinstance(entry.get("lyric_function_seed"), dict) else {}
        function = (
            entry.get("music_function")
            or entry.get("song_function")
            or entry.get("function")
            or entry.get("lyric_function")
            or seed.get("section_job")
            or ""
        )
        if not label and function:
            label = str(function).strip().rstrip(".")
        if not label:
            label = section_id or f"{start:.1f}-{end:.1f}s"
        energy = entry.get("energy_read") or entry.get("energy") or entry.get("section_family") or ""
        return {
            "id": section_id,
            "label": label,
            "start": float(start),
            "end": float(end),
            "time_text": str(time_text),
            "function": str(function),
            "energy": str(energy),
            "source": source,
        }

    def parse_time_range(self, value) -> tuple[float, float] | None:
        if isinstance(value, (list, tuple)) and len(value) >= 2:
            try:
                return float(value[0]), float(value[1])
            except (TypeError, ValueError):
                return None
        text = str(value)
        match = re.search(r"(?P<start>\d+(?:\.\d+)?)\s*(?:-|to|~|–)\s*(?P<end>\d+(?:\.\d+)?)\s*s?", text)
        if not match:
            return None
        start = float(match.group("start"))
        end = float(match.group("end"))
        if end <= start:
            return None
        return start, end

    def refresh_sections_table(self) -> None:
        if not hasattr(self, "sections_tree"):
            return
        self.update_bpm_label()
        self.sections_tree.delete(*self.sections_tree.get_children())
        for idx, section in enumerate(self.song_sections):
            title = f"{section['id']} {section['label']}".strip()
            self.sections_tree.insert(
                "",
                tk.END,
                iid=str(idx),
                values=(
                    section["id"],
                    f"{section['start']:.1f}-{section['end']:.1f}",
                    title[:48],
                ),
            )
        self.refresh_section_detail()

    def refresh_section_detail(self, section: dict | None = None) -> None:
        if not hasattr(self, "section_detail_text"):
            return
        self.section_detail_text.delete("1.0", tk.END)
        if not section:
            if self.section_source:
                self.section_detail_text.insert("1.0", f"Source: {self.short_path(self.section_source)}")
            else:
                self.section_detail_text.insert("1.0", "Click Sections to load a song section map.")
            return
        lines = [
            f"{section['id']} {section['label']}".strip(),
            f"{section['start']:.1f}-{section['end']:.1f}s",
        ]
        if section.get("energy"):
            lines.append(f"Energy: {section['energy']}")
        if section.get("function"):
            lines.append("")
            lines.append(section["function"])
        self.section_detail_text.insert("1.0", "\n".join(lines))

    def on_section_select(self, _event=None) -> None:
        sel = self.sections_tree.selection()
        if not sel:
            return
        idx = int(sel[0])
        if idx >= len(self.song_sections):
            return
        section = self.song_sections[idx]
        self.playhead = float(section["start"])
        self.refresh_section_detail(section)
        self.draw_timeline()
        self.scroll_to_time(float(section["start"]))

    def current_section_index(self) -> int | None:
        if not self.song_sections:
            return None
        for idx, section in enumerate(self.song_sections):
            start = float(section.get("start", 0.0))
            end = float(section.get("end", start))
            if start <= self.playhead < end:
                return idx
        if self.playhead < float(self.song_sections[0].get("start", 0.0)):
            return 0
        return len(self.song_sections) - 1

    def select_section_index(self, idx: int) -> None:
        if not self.song_sections:
            self.load_song_sections()
        if not self.song_sections:
            self.log("No song sections loaded.")
            return
        idx = max(0, min(idx, len(self.song_sections) - 1))
        section = self.song_sections[idx]
        self.playhead = float(section["start"])
        self.refresh_section_detail(section)
        if hasattr(self, "sections_tree") and str(idx) in self.sections_tree.get_children():
            self.sections_tree.selection_set(str(idx))
            self.sections_tree.see(str(idx))
        self.draw_timeline()
        self.scroll_to_time(float(section["start"]))
        self.log(f"Section: {section['id']} {section['label']}")

    def prev_section(self) -> None:
        idx = self.current_section_index()
        if idx is None:
            self.select_section_index(0)
            return
        self.select_section_index(max(0, idx - 1))

    def next_section(self) -> None:
        idx = self.current_section_index()
        if idx is None:
            self.select_section_index(0)
            return
        self.select_section_index(min(len(self.song_sections) - 1, idx + 1))

    def scroll_to_time(self, seconds: float) -> None:
        if not hasattr(self, "canvas"):
            return
        duration = max(self.total_duration, 60.0)
        total_w = LEFT_PAD + duration * self.scale + RIGHT_PAD
        visible_w = max(1, self.canvas.winfo_width())
        scrollable = max(1.0, total_w - visible_w)
        x = max(0.0, self.to_x(seconds) - LEFT_PAD)
        fraction = max(0.0, min(1.0, x / scrollable))
        self.canvas.xview_moveto(fraction)

    def update_section_nav_label(self) -> None:
        if not hasattr(self, "section_nav_var"):
            return
        idx = self.current_section_index()
        if idx is None:
            self.section_nav_var.set("No song sections")
            return
        section = self.song_sections[idx]
        self.section_nav_var.set(
            f"{section['id']} {section['label']}  {section['start']:.1f}-{section['end']:.1f}s"
        )

    def find_bpm_summary(self) -> str:
        self.bpm_source = ""
        summary = self.extract_bpm_from_payload(self.payload)
        if summary:
            self.bpm_source = "recipe"
            return summary
        for path in self.run_document_candidates():
            try:
                payload = yaml.safe_load(path.read_text()) or {}
            except Exception:
                continue
            summary = self.extract_bpm_from_payload(payload)
            if summary:
                self.bpm_source = str(path)
                return summary
        return ""

    def extract_bpm_from_payload(self, payload: dict) -> str:
        if not isinstance(payload, dict):
            return ""
        tempo_and_form = payload.get("tempo_and_form") if isinstance(payload.get("tempo_and_form"), dict) else {}
        if tempo_and_form.get("bpm"):
            return str(tempo_and_form["bpm"])

        tempo_read = payload.get("tempo_read") if isinstance(payload.get("tempo_read"), dict) else {}
        tempo_parts = [str(tempo_read.get(key, "")).strip() for key in ("main_grid", "hook_pulse") if tempo_read.get(key)]
        if tempo_parts:
            return " / ".join(tempo_parts)

        audio_read = payload.get("audio_to_visual_read") if isinstance(payload.get("audio_to_visual_read"), dict) else {}
        if audio_read.get("main_grid_bpm") or audio_read.get("perceived_pulse"):
            parts = []
            if audio_read.get("main_grid_bpm"):
                parts.append(f"{audio_read['main_grid_bpm']} BPM main")
            if audio_read.get("perceived_pulse"):
                parts.append(str(audio_read["perceived_pulse"]))
            return " / ".join(parts)

        sonic = payload.get("sonic_function_read") if isinstance(payload.get("sonic_function_read"), dict) else {}
        if sonic.get("tempo_speed_groove"):
            return str(sonic["tempo_speed_groove"])

        for key in ("bpm", "tempo", "estimated_bpm", "tempo_bpm"):
            if payload.get(key):
                return str(payload[key])

        beats = payload.get("first_beats_seconds")
        if isinstance(beats, list) and len(beats) >= 3:
            intervals = [float(b) - float(a) for a, b in zip(beats, beats[1:]) if float(b) > float(a)]
            if intervals:
                avg = sum(intervals) / len(intervals)
                if avg > 0:
                    return f"{60.0 / avg:.1f} BPM"
        return ""

    def update_bpm_label(self) -> None:
        if not hasattr(self, "bpm_var"):
            return
        if self.bpm_summary:
            self.bpm_var.set(f"BPM: {self.bpm_summary}")
        else:
            self.bpm_var.set("BPM: not loaded")

    def normalize_markers(self) -> None:
        normalized = []
        for idx, marker in enumerate(self.markers):
            if not isinstance(marker, dict):
                continue
            try:
                seconds = float(marker.get("time", 0.0))
            except (TypeError, ValueError):
                continue
            marker_type = str(marker.get("type", "cut")).strip() or "cut"
            if marker_type not in MARKER_COLORS:
                marker_type = "cut"
            normalized.append(
                {
                    "id": str(marker.get("id") or f"M{idx + 1:03d}"),
                    "time": round(max(0.0, min(self.total_duration or seconds, seconds)), 6),
                    "type": marker_type,
                    "label": str(marker.get("label", marker_type)).strip() or marker_type,
                    "color": str(marker.get("color") or MARKER_COLORS[marker_type]),
                    "note": str(marker.get("note", "")),
                    "source": str(marker.get("source", "manual")),
                }
            )
        normalized.sort(key=lambda row: (float(row["time"]), str(row["id"])))
        self.payload["edit_desk_markers"] = normalized

    def next_marker_id(self) -> str:
        used = {str(marker.get("id", "")) for marker in self.markers}
        idx = 1
        while f"M{idx:03d}" in used:
            idx += 1
        return f"M{idx:03d}"

    def add_marker(
        self,
        seconds: float,
        marker_type: str = "cut",
        label: str = "",
        source: str = "manual",
        push_undo: bool = True,
    ) -> dict:
        marker_type = marker_type if marker_type in MARKER_COLORS else "cut"
        if push_undo:
            self.push_undo()
        marker = {
            "id": self.next_marker_id(),
            "time": round(max(0.0, min(self.total_duration or seconds, seconds)), 6),
            "type": marker_type,
            "label": label.strip() or marker_type.replace("_", " "),
            "color": MARKER_COLORS[marker_type],
            "note": "",
            "source": source,
        }
        self.markers.append(marker)
        self.normalize_markers()
        self.refresh_markers_table()
        self.draw_timeline()
        return marker

    def add_marker_at_playhead(self, marker_type: str = "cut", label: str = "") -> None:
        marker = self.add_marker(self.playhead, marker_type=marker_type, label=label, source="manual")
        self.log(f"Marker added: {marker['id']} {marker['label']} at {self.fmt_time(float(marker['time']))}")

    def add_marker_from_panel(self) -> None:
        self.add_marker_at_playhead(self.marker_type_var.get(), self.marker_label_var.get())

    def refresh_markers_table(self) -> None:
        if not hasattr(self, "markers_tree"):
            return
        self.normalize_markers()
        self.markers_tree.delete(*self.markers_tree.get_children())
        for marker in self.markers:
            marker_id = str(marker.get("id", ""))
            self.markers_tree.insert(
                "",
                tk.END,
                iid=marker_id,
                values=(
                    self.fmt_time(float(marker.get("time", 0.0))),
                    marker.get("type", "cut"),
                    str(marker.get("label", ""))[:44],
                ),
            )

    def selected_marker(self) -> dict | None:
        if not hasattr(self, "markers_tree"):
            return None
        sel = self.markers_tree.selection()
        if not sel:
            return None
        marker_id = sel[0]
        for marker in self.markers:
            if str(marker.get("id")) == marker_id:
                return marker
        return None

    def on_marker_select(self, _event=None) -> None:
        marker = self.selected_marker()
        if not marker:
            return
        self.marker_type_var.set(str(marker.get("type", "cut")))
        self.marker_label_var.set(str(marker.get("label", "")))

    def jump_to_selected_marker(self) -> None:
        marker = self.selected_marker()
        if not marker:
            return
        self.playhead = max(0.0, min(self.total_duration, float(marker.get("time", 0.0))))
        self.draw_timeline()
        self.scroll_to_time(self.playhead)
        self.log(f"Marker: {marker.get('id')} {marker.get('label')}")

    def delete_selected_marker(self) -> None:
        marker = self.selected_marker()
        if not marker:
            return
        self.push_undo()
        marker_id = str(marker.get("id"))
        self.payload["edit_desk_markers"] = [row for row in self.markers if str(row.get("id")) != marker_id]
        self.refresh_markers_table()
        self.draw_timeline()
        self.log("Marker deleted.")

    def marker_exists_near(self, seconds: float, marker_type: str, tolerance: float = 0.04) -> bool:
        for marker in self.markers:
            if str(marker.get("type")) != marker_type:
                continue
            if abs(float(marker.get("time", 0.0)) - seconds) <= tolerance:
                return True
        return False

    def generate_cue_markers(self) -> None:
        if not self.timeline:
            return
        additions: list[tuple[float, str, str, str]] = []
        for section in self.song_sections:
            start = float(section.get("start", 0.0))
            label = f"{section.get('id', '')} {section.get('label', '')}".strip() or "section"
            additions.append((start, "section", label, "section"))
        for seconds, label in self.lyric_marks[:160]:
            additions.append((seconds, "lyric", label[:40] or "lyric", "lyrics"))
        if self.waveform:
            min_gap = 0.35
            last = -999.0
            duration = max(self.total_duration, 1.0)
            for idx, peak in enumerate(self.waveform):
                if peak < 0.72:
                    continue
                seconds = (idx / max(1, len(self.waveform) - 1)) * duration
                if seconds - last < min_gap:
                    continue
                additions.append((seconds, "beat", "wave peak", "waveform"))
                last = seconds
                if sum(1 for row in additions if row[1] == "beat") >= 80:
                    break
        if not additions:
            self.log("No section, lyric, or waveform cues available.")
            return
        self.push_undo()
        created = 0
        for seconds, marker_type, label, source in additions:
            if seconds < 0 or seconds > self.total_duration:
                continue
            if self.marker_exists_near(seconds, marker_type):
                continue
            self.add_marker(seconds, marker_type=marker_type, label=label, source=source, push_undo=False)
            created += 1
        self.normalize_markers()
        self.refresh_markers_table()
        self.draw_timeline()
        self.log(f"Cue markers generated: {created}")

    def queue_trim_preview(self, mode: str = "selected") -> None:
        if not hasattr(self, "root") or not hasattr(self, "trim_canvas"):
            return
        self.pending_trim_mode = mode
        if self.trim_preview_job is not None:
            self.root.after_cancel(self.trim_preview_job)
        self.trim_preview_job = self.root.after(90, self.update_trim_preview)

    def update_trim_preview(self) -> None:
        self.trim_preview_job = None
        self.trim_canvas.delete("all")
        self.trim_image_refs = []
        idx = self.selected_index
        width = max(320, self.trim_canvas.winfo_width())
        if idx is None or idx >= len(self.timeline):
            self.trim_canvas.create_text(12, 82, text="No clip selected", fill=UI_MUTED_DARK, anchor=tk.W)
            self.trim_status_var.set("Select a clip to show source cut frames.")
            return

        row = self.timeline[idx]
        source = self.resolve_source_path(row.get("source", ""))
        source_in = float(row.get("source_in", 0.0))
        source_out = float(row.get("source_out", source_in))
        mode = self.pending_trim_mode
        frames: list[tuple[str, Path, float, bool]] = []
        if mode == "left" and idx > 0:
            prev = self.timeline[idx - 1]
            prev_source = self.resolve_source_path(prev.get("source", ""))
            prev_out = max(float(prev.get("source_in", 0.0)), float(prev.get("source_out", 0.0)) - 0.04)
            frames = [("PREV OUT", prev_source, prev_out, False), ("THIS IN", source, source_in, True)]
        elif mode == "right" and idx + 1 < len(self.timeline):
            next_row = self.timeline[idx + 1]
            next_source = self.resolve_source_path(next_row.get("source", ""))
            next_in = float(next_row.get("source_in", 0.0))
            frames = [("THIS OUT", source, max(source_in, source_out - 0.04), True), ("NEXT IN", next_source, next_in, False)]
        else:
            frames = [("IN", source, source_in, mode == "left"), ("OUT", source, max(source_in, source_out - 0.04), mode == "right")]
        panel_w = max(120, int((width - 16 - (len(frames) - 1) * 10) / max(1, len(frames))))
        panel_h = 106

        for pos, (label, frame_source, seconds, active) in enumerate(frames):
            x = 8 + pos * (panel_w + 10)
            outline = UI_WARN if active else UI_BORDER
            self.trim_canvas.create_rectangle(x, 8, x + panel_w, 8 + panel_h, fill=UI_VIEWER, outline=outline, width=2)
            if not frame_source.exists():
                self.trim_canvas.create_text(x + 10, 54, text="Missing source", fill=UI_DANGER, anchor=tk.W)
            else:
                photo = self.frame_photo(frame_source, seconds, panel_w - 4, panel_h - 24)
                if photo is not None:
                    self.trim_image_refs.append(photo)
                    self.trim_canvas.create_image(x + 2, 10, image=photo, anchor=tk.NW)
                else:
                    self.trim_canvas.create_text(x + 12, 54, text="Frame unavailable", fill=UI_MUTED_DARK, anchor=tk.W)
            self.trim_canvas.create_rectangle(x + 2, 8 + panel_h - 22, x + panel_w - 2, 8 + panel_h - 2, fill=UI_FIELD, outline="")
            self.trim_canvas.create_text(
                x + 8,
                8 + panel_h - 18,
                text=f"{label}  {seconds:.3f}s",
                fill=UI_TEXT if active else UI_TEXT_SOFT,
                anchor=tk.NW,
                font=("Helvetica", 10, "bold" if active else "normal"),
            )

        self.trim_status_var.set(
            f"{row.get('slot', f'clip-{idx + 1}')} | source {source_in:.3f}s - {source_out:.3f}s | edit-point compare"
        )

    def resolve_source_path(self, value: str | Path) -> Path:
        path = Path(value)
        if path.is_absolute():
            return path
        return self.run_root / path

    def frame_photo(self, source: Path, seconds: float, width: int, height: int):
        if Image is None or ImageTk is None:
            return None
        key = (str(source), round(max(0.0, seconds), 1), width, height)
        if key in self.frame_cache:
            return self.frame_cache[key]
        try:
            import cv2
            import numpy as np

            cap = cv2.VideoCapture(str(source))
            if not cap.isOpened():
                return None
            cap.set(cv2.CAP_PROP_POS_MSEC, max(0.0, seconds) * 1000.0)
            ok, frame = cap.read()
            if not ok:
                frame_count = cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0
                if frame_count:
                    cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, int(frame_count) - 1))
                    ok, frame = cap.read()
            cap.release()
            if not ok:
                return None
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = Image.fromarray(np.asarray(rgb))
            image.thumbnail((width, height))
            canvas = Image.new("RGB", (width, height), UI_VIEWER)
            x = (width - image.width) // 2
            y = (height - image.height) // 2
            canvas.paste(image, (x, y))
            photo = ImageTk.PhotoImage(canvas)
            self.frame_cache[key] = photo
            return photo
        except Exception:
            return None

    def load_source_from_row(self, row: dict, select_tab: bool = False) -> None:
        source = self.resolve_source_path(row.get("source", ""))
        source_in = float(row.get("source_in", 0.0))
        source_out = float(row.get("source_out", source_in))
        self.load_source_view(source, source_in=source_in, source_out=source_out, select_tab=select_tab)

    def load_source_view(
        self,
        source: Path,
        source_in: float = 0.0,
        source_out: float | None = None,
        select_tab: bool = False,
    ) -> None:
        if not hasattr(self, "source_canvas"):
            return
        source = self.normalize_media_path(source)
        duration = self.source_duration_for_path(source)
        self.source_view_path = source
        self.source_view_duration = duration
        self.source_view_in = max(0.0, min(source_in, max(0.0, duration - MIN_DURATION))) if duration > 0 else max(0.0, source_in)
        default_out = duration if source_out is None else source_out
        self.source_view_out = max(self.source_view_in + MIN_DURATION, default_out)
        if duration > 0:
            self.source_view_out = min(duration, self.source_view_out)
        self.source_view_time = self.source_view_in
        self.source_in_var.set(f"{self.source_view_in:.6f}")
        self.source_out_var.set(f"{self.source_view_out:.6f}")
        self.source_scrub.configure(to=max(duration, 1.0))
        self.source_scrub_var.set(self.source_view_time)
        self.source_title_var.set(self.compact_text(source.name, 34))
        self.source_status_var.set(self.short_path(source))
        if select_tab:
            self.set_workspace("Edit")
        self.queue_source_preview()

    def queue_source_preview(self) -> None:
        if not hasattr(self, "root") or not hasattr(self, "source_canvas"):
            return
        if self.source_preview_job is not None:
            self.root.after_cancel(self.source_preview_job)
        self.source_preview_job = self.root.after(60, self.update_source_preview)

    def update_source_preview(self) -> None:
        self.source_preview_job = None
        self.source_canvas.delete("all")
        self.source_image_ref = None
        width = max(260, self.source_canvas.winfo_width())
        height = max(128, self.source_canvas.winfo_height())
        self.source_canvas.create_rectangle(0, 0, width, height, fill=UI_VIEWER, outline="")
        if not self.source_view_path:
            self.source_canvas.create_text(width / 2, height / 2, text="No source loaded", fill=UI_MUTED_DARK, font=("Helvetica", 12, "bold"))
            self.source_time_var.set("0:00.0 / 0:00.0")
            return
        self.source_time_var.set(f"{self.fmt_time(self.source_view_time)} / {self.fmt_time(self.source_view_duration)}")
        if not self.source_view_path.exists():
            self.source_canvas.create_text(width / 2, height / 2, text=f"Missing source\n{self.short_path(self.source_view_path)}", fill=UI_DANGER, justify=tk.CENTER)
            return
        photo = self.frame_photo(self.source_view_path, self.source_view_time, width - 8, height - 28)
        if photo is None:
            self.source_canvas.create_text(width / 2, height / 2, text="Frame unavailable", fill=UI_MUTED_DARK, font=("Helvetica", 12, "bold"))
            return
        self.source_image_ref = photo
        self.source_canvas.create_image(width / 2, (height - 20) / 2, image=photo, anchor=tk.CENTER)
        self.source_canvas.create_rectangle(0, height - 24, width, height, fill=UI_FIELD, outline="")
        self.source_canvas.create_text(
            8,
            height - 19,
            text=f"IN {self.source_view_in:.2f}s  OUT {self.source_view_out:.2f}s",
            fill=UI_TEXT_SOFT,
            anchor=tk.NW,
            font=("Helvetica", 9, "bold"),
        )

    def refresh_source_viewer(self) -> None:
        if not hasattr(self, "source_canvas"):
            return
        if self.source_view_path is None and self.selected_index is not None and self.selected_index < len(self.timeline):
            self.load_source_from_row(self.timeline[self.selected_index])
            return
        self.queue_source_preview()

    def on_source_scrub(self, value: str) -> None:
        try:
            seconds = float(value)
        except ValueError:
            return
        self.source_view_time = max(0.0, min(self.source_view_duration, seconds))
        self.queue_source_preview()

    def set_source_view_in(self) -> None:
        if not self.source_view_path:
            return
        self.source_view_in = max(0.0, min(self.source_view_time, max(0.0, self.source_view_out - MIN_DURATION)))
        self.source_in_var.set(f"{self.source_view_in:.6f}")
        self.queue_source_preview()
        self.log("Source In set.")

    def set_source_view_out(self) -> None:
        if not self.source_view_path:
            return
        duration = self.source_view_duration or self.source_duration_for_path(self.source_view_path)
        self.source_view_out = max(self.source_view_in + MIN_DURATION, min(duration if duration > 0 else self.source_view_time, self.source_view_time))
        self.source_out_var.set(f"{self.source_view_out:.6f}")
        self.queue_source_preview()
        self.log("Source Out set.")

    def append_source_selection(self) -> None:
        if not self.source_view_path:
            return
        try:
            source_in = max(0.0, self.parse_seconds_value(self.source_in_var.get()))
            source_out = max(source_in + MIN_DURATION, self.parse_seconds_value(self.source_out_var.get()))
        except ValueError as exc:
            messagebox.showerror("Source", f"Could not parse source in/out: {exc}")
            return
        duration = self.source_duration_for_path(self.source_view_path)
        if duration > 0:
            source_out = min(duration, source_out)
        clip_duration = max(MIN_DURATION, source_out - source_in)
        clip = self.build_video_clip(self.source_view_path, duration or source_out, note="Appended from Source viewer.")
        clip["source_in"] = round(source_in, 6)
        clip["source_out"] = round(source_out, 6)
        clip["output_duration"] = round(clip_duration, 6)

        had_timeline = bool(self.timeline)
        if had_timeline:
            self.push_undo()
        else:
            self.start_multi_video_session(self.source_view_path)
        self.ensure_unique_clip_slots([clip])
        self.timeline.append(clip)
        self.selected_index = len(self.timeline) - 1
        self.recalculate_timeline()
        self.playhead = float(self.timeline[self.selected_index].get("output_in", 0.0))
        self.refresh_auto_video_sections()
        self.refresh_all()
        self.log("Source selection appended.")

    def queue_viewer_preview(self) -> None:
        if not hasattr(self, "root") or not hasattr(self, "viewer_canvas"):
            return
        if self.viewer_preview_job is not None:
            self.root.after_cancel(self.viewer_preview_job)
        self.viewer_preview_job = self.root.after(60, self.update_viewer_preview)

    def update_viewer_preview(self) -> None:
        self.viewer_preview_job = None
        self.viewer_canvas.delete("all")
        self.viewer_image_ref = None
        width = max(320, self.viewer_canvas.winfo_width())
        height = max(220, self.viewer_canvas.winfo_height())
        self.viewer_canvas.create_rectangle(0, 0, width, height, fill=UI_VIEWER, outline="")
        self.update_viewer_time_label()

        clip = self.active_clip_at_output(self.playhead)
        if clip is None:
            self.viewer_canvas.create_text(width / 2, height / 2, text="Open a recipe or video", fill=UI_MUTED_DARK, font=("Helvetica", 15, "bold"))
            return
        idx, row = clip
        source = self.resolve_source_path(row.get("source", ""))
        source_time = self.source_time_for_output(row, self.playhead)
        label = str(row.get("slot", f"clip-{idx + 1}"))
        if not source.exists():
            self.viewer_canvas.create_text(width / 2, height / 2, text=f"Missing source\n{self.short_path(source)}", fill=UI_DANGER, justify=tk.CENTER)
            return

        photo = self.frame_photo(source, source_time, width - 12, height - 34)
        if photo is None:
            self.viewer_canvas.create_text(width / 2, height / 2, text="Frame unavailable", fill=UI_MUTED_DARK, font=("Helvetica", 14, "bold"))
            return
        self.viewer_image_ref = photo
        self.viewer_canvas.create_image(width / 2, (height - 18) / 2, image=photo, anchor=tk.CENTER)
        self.viewer_canvas.create_rectangle(0, height - 30, width, height, fill=UI_FIELD, outline="")
        max_label_chars = max(18, int(max(120, width - 170) / 7))
        self.viewer_canvas.create_text(12, height - 22, text=label[:max_label_chars], fill=UI_TEXT_SOFT, anchor=tk.NW, font=("Helvetica", 10, "bold"))
        self.viewer_canvas.create_text(width - 12, height - 22, text=f"source {source_time:.2f}s", fill=UI_MUTED, anchor=tk.NE, font=("Helvetica", 10))

    def active_clip_at_output(self, seconds: float) -> tuple[int, dict] | None:
        if not self.timeline:
            return None
        for idx, row in enumerate(self.timeline):
            output_in = float(row.get("output_in", 0.0))
            output_out = float(row.get("output_out", output_in))
            if output_in <= seconds < output_out:
                return idx, row
        if seconds >= self.total_duration:
            return len(self.timeline) - 1, self.timeline[-1]
        if self.selected_index is not None and self.selected_index < len(self.timeline):
            return self.selected_index, self.timeline[self.selected_index]
        return 0, self.timeline[0]

    def source_time_for_output(self, row: dict, output_seconds: float) -> float:
        output_in = float(row.get("output_in", 0.0))
        source_in = float(row.get("source_in", 0.0))
        source_out = float(row.get("source_out", source_in))
        output_duration = max(MIN_DURATION, float(row.get("output_duration", source_out - source_in)))
        speed = max(MIN_DURATION, (source_out - source_in) / output_duration)
        source_time = source_in + max(0.0, output_seconds - output_in) * speed
        return max(source_in, min(source_out, source_time))

    def update_viewer_time_label(self) -> None:
        if hasattr(self, "viewer_time_var"):
            self.viewer_time_var.set(f"{self.fmt_time(self.playhead)} / {self.fmt_time(self.total_duration)}")

    def nudge_playhead(self, delta: float) -> None:
        self.playhead = max(0.0, min(self.total_duration, self.playhead + delta))
        self.draw_timeline()
        self.scroll_to_time(self.playhead)

    def toggle_playback(self) -> None:
        if self.is_playing:
            self.stop_playback()
            return
        if not self.timeline:
            return
        self.is_playing = True
        self.last_play_tick = time.monotonic()
        if hasattr(self, "play_button"):
            self.play_button.configure(text="Pause")
        self.playback_tick()

    def playback_tick(self) -> None:
        if not self.is_playing:
            return
        now = time.monotonic()
        elapsed = max(0.0, min(0.25, now - self.last_play_tick))
        self.last_play_tick = now
        self.playhead = min(self.total_duration, self.playhead + elapsed)
        self.draw_timeline()
        if self.playhead >= self.total_duration:
            self.stop_playback()
            return
        self.play_job = self.root.after(80, self.playback_tick)

    def stop_playback(self) -> None:
        self.is_playing = False
        if self.play_job is not None and hasattr(self, "root"):
            self.root.after_cancel(self.play_job)
            self.play_job = None
        if hasattr(self, "play_button"):
            self.play_button.configure(text="Play")

    def draw_timeline(self) -> None:
        if not hasattr(self, "canvas"):
            return
        self.canvas.delete("all")
        width = max(self.canvas.winfo_width(), 1000)
        height = max(self.canvas.winfo_height(), 560)
        duration = max(self.total_duration, 60.0)
        base_scale = max(4.0, (width - LEFT_PAD - RIGHT_PAD) / duration)
        self.scale = max(3.0, min(120.0, base_scale * self.zoom))
        timeline_w = duration * self.scale
        self.canvas.configure(scrollregion=(0, 0, LEFT_PAD + timeline_w + RIGHT_PAD, height))

        self.canvas.create_rectangle(0, 0, LEFT_PAD - 1, height, fill=UI_TOP, outline=UI_BORDER_SOFT)
        self.draw_lane_header("Time", TOP_PAD, WORK_Y - 4)

        for sec in self.time_ticks(duration):
            x = self.to_x(sec)
            major = sec % 10 == 0
            color = UI_BORDER if major else UI_BORDER_SOFT
            self.canvas.create_line(x, TOP_PAD, x, height, fill=color)
            if major:
                self.canvas.create_text(x + 3, AXIS_Y, text=self.fmt_time(sec), fill=UI_MUTED, anchor=tk.NW, font=("Helvetica", 10))

        self.draw_work_area()
        self.draw_markers_lane()
        self.draw_waveform()
        self.draw_sections_lane()
        self.draw_effects()
        self.draw_clips()
        self.draw_audio_placeholder()

        px = self.to_x(self.playhead)
        self.canvas.create_polygon(px - 6, TOP_PAD + 2, px + 6, TOP_PAD + 2, px, TOP_PAD + 12, fill=UI_WARN, outline="")
        self.canvas.create_line(px, TOP_PAD + 12, px, AUDIO_Y + AUDIO_H, fill=UI_WARN, width=2)
        self.canvas.create_text(px + 6, TOP_PAD + 4, text=self.fmt_time(self.playhead), fill=UI_WARN, anchor=tk.NW, font=("Helvetica", 10, "bold"))
        self.update_section_nav_label()
        self.queue_viewer_preview()

    def draw_lane_header(self, label: str, y0: float, y1: float, sublabel: str = "") -> None:
        self.canvas.create_rectangle(0, y0, LEFT_PAD - 1, y1, fill=UI_TOP, outline=UI_BORDER_SOFT)
        lane_h = y1 - y0
        text_y = y0 + max(5, min(9, lane_h / 3))
        self.canvas.create_text(12, text_y, text=label, fill=UI_TEXT_SOFT, anchor=tk.NW, font=("Helvetica", 10, "bold"))
        if sublabel and lane_h >= 34:
            self.canvas.create_text(12, y0 + 24, text=sublabel, fill=UI_MUTED_DARK, anchor=tk.NW, font=("Helvetica", 8))

    def draw_work_area(self) -> None:
        x0 = LEFT_PAD
        x1 = self.to_x(max(self.total_duration, 60.0))
        self.draw_lane_header("Work Area", WORK_Y, WORK_Y + WORK_H, "render range")
        self.canvas.create_rectangle(x0, WORK_Y, x1, WORK_Y + WORK_H, fill=UI_PANEL_ALT, outline=UI_BORDER_SOFT)
        range_in = 0.0
        range_out = self.total_duration
        if self.selected_index is not None and self.selected_index < len(self.timeline):
            row = self.timeline[self.selected_index]
            range_in = float(row.get("output_in", 0.0))
            range_out = float(row.get("output_out", range_in))
        if range_out > range_in:
            rx0 = self.to_x(range_in)
            rx1 = self.to_x(range_out)
            self.canvas.create_rectangle(rx0, WORK_Y + 4, rx1, WORK_Y + WORK_H - 4, fill=UI_ACCENT_DARK, outline=UI_ACCENT)
            if rx1 - rx0 > 90:
                self.canvas.create_text(rx0 + 6, WORK_Y + 5, text="render range", fill=UI_TEXT_SOFT, anchor=tk.NW, font=("Helvetica", 9, "bold"))

    def draw_waveform(self) -> None:
        x0 = LEFT_PAD
        x1 = self.to_x(max(self.total_duration, 60.0))
        y_mid = WAVE_Y + WAVE_H / 2
        self.draw_lane_header("A1 Guide", WAVE_Y, WAVE_Y + WAVE_H, "song waveform")
        self.canvas.create_rectangle(x0, WAVE_Y, x1, WAVE_Y + WAVE_H, fill=UI_PANEL_ALT, outline=UI_BORDER_SOFT)
        if not self.waveform:
            self.canvas.create_text(x0 + 10, y_mid, text="Load Song for waveform", fill=UI_MUTED_DARK, anchor=tk.W, font=("Helvetica", 11))
        else:
            step = max(1, int(len(self.waveform) / max(1, x1 - x0)))
            points = self.waveform[::step]
            for i, peak in enumerate(points):
                x = x0 + i
                if x > x1:
                    break
                amp = min(1.0, abs(peak)) * (WAVE_H / 2 - 3)
                self.canvas.create_line(x, y_mid - amp, x, y_mid + amp, fill=UI_ACCENT)
        if self.bpm_summary:
            self.canvas.create_text(x0 + 10, WAVE_Y + 6, text=f"BPM: {self.bpm_summary[:92]}", fill=UI_TEXT_SOFT, anchor=tk.NW, font=("Helvetica", 9))

    def draw_sections_lane(self) -> None:
        x0 = LEFT_PAD
        x1 = self.to_x(max(self.total_duration, 60.0))
        self.draw_lane_header("Story", SECTION_Y, SECTION_Y + SECTION_H, "sections")
        self.canvas.create_rectangle(x0, SECTION_Y, x1, SECTION_Y + SECTION_H, fill=UI_PANEL_ALT, outline=UI_BORDER_SOFT)
        if not self.song_sections:
            self.canvas.create_text(x0 + 10, SECTION_Y + 10, text="Load Sections", fill=UI_MUTED_DARK, anchor=tk.NW, font=("Helvetica", 11))
        palette = ["#1f3b52", "#35404f", "#3f3a54", "#3b4639", "#4a3a3f", "#2f464b"]
        current_idx = self.current_section_index()
        for idx, section in enumerate(self.song_sections):
            start = float(section.get("start", 0.0))
            end = float(section.get("end", start))
            if end < 0 or start > self.total_duration:
                continue
            sx0 = self.to_x(max(0.0, start))
            sx1 = self.to_x(min(max(self.total_duration, 60.0), end))
            fill = palette[idx % len(palette)]
            outline = UI_WARN if idx == current_idx else UI_BG
            width = 2 if idx == current_idx else 1
            self.canvas.create_rectangle(sx0, SECTION_Y, sx1, SECTION_Y + SECTION_H, fill=fill, outline=outline, width=width)
            label = f"{section.get('id', '')} {section.get('label', '')}".strip()
            if sx1 - sx0 > 42:
                self.canvas.create_text(sx0 + 4, SECTION_Y + 5, text=label[:28], fill=UI_TEXT, anchor=tk.NW, font=("Helvetica", 9, "bold"))
        for sec, label in self.lyric_marks[:120]:
            if 0 <= sec <= self.total_duration:
                x = self.to_x(sec)
                self.canvas.create_line(x, SECTION_Y + SECTION_H - 8, x, SECTION_Y + SECTION_H, fill=MARKER_COLORS["lyric"])
                if self.scale > 10:
                    self.canvas.create_text(x + 3, SECTION_Y + SECTION_H - 16, text=label[:18], fill=MARKER_COLORS["lyric"], anchor=tk.NW, font=("Helvetica", 8))

    def draw_effects(self) -> None:
        for effect in self.payload.get("effects", []) or []:
            if "start" not in effect:
                continue
            sec = float(effect["start"])
            if 0 <= sec <= self.total_duration:
                x = self.to_x(sec)
                self.canvas.create_line(x, CLIP_Y - 14, x, CLIP_Y - 2, fill="#b083c7", width=2)

    def draw_markers_lane(self) -> None:
        x0 = LEFT_PAD
        x1 = self.to_x(max(self.total_duration, 60.0))
        self.draw_lane_header("Markers", MARKER_Y, MARKER_Y + MARKER_H, "cue points")
        self.canvas.create_rectangle(x0, MARKER_Y, x1, MARKER_Y + MARKER_H, fill=UI_PANEL_ALT, outline=UI_BORDER_SOFT)
        if not self.markers:
            self.canvas.create_text(x0 + 10, MARKER_Y + 7, text="M marker | cue markers", fill=UI_MUTED_DARK, anchor=tk.NW, font=("Helvetica", 10))
            return
        for marker in self.markers:
            seconds = float(marker.get("time", 0.0))
            if seconds < 0 or seconds > self.total_duration:
                continue
            x = self.to_x(seconds)
            marker_type = str(marker.get("type", "cut"))
            color = str(marker.get("color") or MARKER_COLORS.get(marker_type, UI_WARN))
            self.canvas.create_line(x, MARKER_Y + 3, x, MARKER_Y + MARKER_H - 3, fill=color, width=2)
            self.canvas.create_polygon(x - 5, MARKER_Y + 3, x + 5, MARKER_Y + 3, x, MARKER_Y + 10, fill=color, outline="")
            label = str(marker.get("label", ""))
            if self.scale > 12 and label:
                self.canvas.create_text(x + 5, MARKER_Y + 7, text=label[:18], fill=color, anchor=tk.NW, font=("Helvetica", 8, "bold"))

    def draw_clips(self) -> None:
        palette = ["#24506a", "#40536b", "#4d4968", "#475a48", "#60424d", "#325b59", "#554f70"]
        self.draw_lane_header("V1", CLIP_Y, CLIP_Y + CLIP_H, "video clips")
        for idx, row in enumerate(self.timeline):
            y = CLIP_Y
            x0 = self.to_x(float(row.get("output_in", 0.0)))
            x1 = self.to_x(float(row.get("output_out", 0.0)))
            color = palette[idx % len(palette)]
            outline = UI_WARN if idx == self.selected_index else UI_BORDER_SOFT
            self.canvas.create_rectangle(x0, y, x1, y + CLIP_H, fill=color, outline=outline, width=2)
            self.canvas.create_rectangle(x0, y, x0 + HANDLE_W, y + CLIP_H, fill=UI_HANDLE, outline="")
            self.canvas.create_rectangle(x1 - HANDLE_W, y, x1, y + CLIP_H, fill=UI_HANDLE, outline="")
            slot = str(row.get("slot", f"clip-{idx + 1}"))
            dur = float(row.get("output_duration", 0.0))
            label_width = max(1, x1 - x0 - 18)
            if label_width > 36:
                max_chars = max(4, int(label_width / 7))
                self.canvas.create_text(x0 + 12, y + 7, text=slot[:max_chars], fill=UI_TEXT, anchor=tk.NW, font=("Helvetica", 10, "bold"))
            if label_width > 66:
                self.canvas.create_text(x0 + 12, y + 21, text=f"{dur:.2f}s  {float(row.get('speed_factor', 1.0)):.2f}x", fill=UI_TEXT_SOFT, anchor=tk.NW, font=("Helvetica", 9))

    def draw_audio_placeholder(self) -> None:
        x0 = LEFT_PAD
        x1 = self.to_x(max(self.total_duration, 60.0))
        self.draw_lane_header("A1", AUDIO_Y, AUDIO_Y + AUDIO_H, "master audio")
        self.canvas.create_rectangle(x0, AUDIO_Y, x1, AUDIO_Y + AUDIO_H, fill=UI_FIELD, outline=UI_BORDER_SOFT)
        text = "master song audio guide"
        if self.audio_path_text:
            text = f"master audio: {Path(self.audio_path_text).name}"
        self.canvas.create_text(x0 + 10, AUDIO_Y + 7, text=text[:96], fill=UI_MUTED, anchor=tk.NW, font=("Helvetica", 9, "bold"))

    def time_ticks(self, duration: float) -> list[int]:
        step = 1
        if duration > 120:
            step = 5
        if duration > 240:
            step = 10
        return list(range(0, int(math.ceil(duration)) + 1, step))

    def to_x(self, seconds: float) -> float:
        return LEFT_PAD + seconds * self.scale

    def from_x(self, x: float) -> float:
        return max(0.0, (x - LEFT_PAD) / self.scale)

    def fmt_time(self, sec: float) -> str:
        minutes = int(sec // 60)
        seconds = sec - minutes * 60
        return f"{minutes}:{seconds:04.1f}"

    def parse_seconds_value(self, value: str) -> float:
        text = value.strip().lower().rstrip("s").strip()
        if ":" not in text:
            return float(text)
        parts = [float(part) for part in text.split(":")]
        seconds = 0.0
        for part in parts:
            seconds = seconds * 60.0 + part
        return seconds

    def parse_speed_value(self, value: str) -> float:
        text = value.strip().lower()
        if not text:
            return 0.0
        if text.endswith("%"):
            return float(text[:-1].strip()) / 100.0
        if text.endswith("x"):
            return float(text[:-1].strip())
        return float(text)

    def snap_targets(self, exclude_clip_idx: int | None = None) -> list[float]:
        targets = [0.0, self.total_duration]
        for idx, row in enumerate(self.timeline):
            if idx == exclude_clip_idx:
                continue
            targets.append(float(row.get("output_in", 0.0)))
            targets.append(float(row.get("output_out", 0.0)))
        for section in self.song_sections:
            targets.append(float(section.get("start", 0.0)))
            targets.append(float(section.get("end", section.get("start", 0.0))))
        for seconds, _label in self.lyric_marks:
            targets.append(float(seconds))
        for marker in self.markers:
            targets.append(float(marker.get("time", 0.0)))
        return [target for target in targets if 0.0 <= target <= max(self.total_duration, 0.0)]

    def snap_time(self, seconds: float, exclude_clip_idx: int | None = None, force: bool = False) -> float:
        seconds = max(0.0, min(self.total_duration, seconds))
        if not force and not self.snapping_enabled:
            return seconds
        threshold = max(0.02, SNAP_PX / max(self.scale, 1.0))
        best = seconds
        best_dist = threshold
        for target in self.snap_targets(exclude_clip_idx=exclude_clip_idx):
            dist = abs(target - seconds)
            if dist <= best_dist:
                best = target
                best_dist = dist
        return max(0.0, min(self.total_duration, best))

    def snap_allowed_for_event(self, event) -> bool:
        # Tk state bit 0x0008 is Alt/Option on common macOS/Tk builds.
        return self.snapping_enabled and not (getattr(event, "state", 0) & 0x0008)

    def on_speed_slider(self, value: str) -> None:
        try:
            speed = float(value)
        except ValueError:
            return
        self.speed_slider_label.set(f"Speed slider: {speed:.2f}x")

    def focus_is_text_input(self) -> bool:
        if not hasattr(self, "root"):
            return False
        widget = self.root.focus_get()
        if widget is None:
            return False
        return widget.winfo_class() in {"Entry", "Text", "TCombobox"}

    def command_modifier_active(self, event) -> bool:
        state = getattr(event, "state", 0)
        return bool(state & (0x0004 | 0x0010))

    def on_key_press(self, event) -> str | None:
        if self.focus_is_text_input():
            return None
        key = (event.keysym or "").lower()
        char = (event.char or "").lower()
        action_key = char or key
        command = self.command_modifier_active(event)
        shift = bool(getattr(event, "state", 0) & 0x0001)
        if command and action_key == "z":
            if shift:
                self.redo()
            else:
                self.undo()
            return "break"
        if command and action_key == "y":
            self.redo()
            return "break"
        if command and action_key == "s":
            self.save_draft()
            return "break"
        if command and action_key == "o":
            self.open_recipe()
            return "break"
        if command and action_key == "d":
            self.duplicate_selected()
            return "break"
        if key == "space":
            self.toggle_playback()
            return "break"
        if key in {"delete", "backspace"}:
            self.delete_selected()
            return "break"
        if key == "escape":
            self.stop_playback()
            self.drag = None
            self.log("Playback stopped.")
            return "break"
        if char == "b":
            self.split_selected()
            return "break"
        if char == "s":
            self.toggle_snapping()
            return "break"
        if char == "m":
            self.add_marker_at_playhead("cut")
            return "break"
        if char == "i":
            self.set_source_view_in()
            return "break"
        if char == "o":
            self.set_source_view_out()
            return "break"
        if char == "q":
            self.ripple_trim_to_playhead("left")
            return "break"
        if char == "w":
            self.ripple_trim_to_playhead("right")
            return "break"
        if key in {"equal", "plus"} or char == "=":
            self.zoom_at_canvas_center(1.15)
            return "break"
        if key == "minus" or char == "-":
            self.zoom_at_canvas_center(0.87)
            return "break"
        if key == "left":
            self.nudge_playhead(-1.0 / FPS)
            return "break"
        if key == "right":
            self.nudge_playhead(1.0 / FPS)
            return "break"
        if key == "up":
            self.jump_to_edit_point(-1)
            return "break"
        if key == "down":
            self.jump_to_edit_point(1)
            return "break"
        return None

    def on_tree_select(self, _event=None) -> None:
        sel = self.clip_tree.selection()
        if not sel:
            return
        self.selected_index = int(sel[0])
        row = self.timeline[self.selected_index]
        self.playhead = float(row.get("output_in", 0.0))
        self.refresh_inspector()
        self.draw_timeline()

    def hit_test(self, x: float, y: float) -> Hit | None:
        if y < CLIP_Y or y > CLIP_Y + CLIP_H:
            return None
        for idx, row in enumerate(self.timeline):
            x0 = self.to_x(float(row.get("output_in", 0.0)))
            x1 = self.to_x(float(row.get("output_out", 0.0)))
            if x0 <= x <= x0 + HANDLE_W + 4:
                return Hit(idx, "left")
            if x1 - HANDLE_W - 4 <= x <= x1:
                return Hit(idx, "right")
            if x0 <= x <= x1:
                return Hit(idx, "body")
        return None

    def on_canvas_down(self, event) -> None:
        x = self.canvas.canvasx(event.x)
        y = self.canvas.canvasy(event.y)
        hit = self.hit_test(x, y)
        clicked_time = min(self.total_duration, self.from_x(x))
        if self.tool_mode == "hand":
            self.canvas.scan_mark(event.x, event.y)
            self.drag = {"hit": Hit(-1, "pan")}
            return
        self.playhead = self.snap_time(clicked_time) if self.snap_allowed_for_event(event) else clicked_time
        if self.tool_mode == "marker":
            self.add_marker_at_playhead("cut")
            self.drag = None
            return
        if hit:
            self.selected_index = hit.index
            self.refresh_tree()
            self.refresh_inspector()
            if self.tool_mode == "razor" and hit.mode == "body":
                self.split_selected()
                return
            row = copy.deepcopy(self.timeline[hit.index])
            self.drag = {"hit": hit, "start_time": self.from_x(x), "row": row, "snapshot": copy.deepcopy(self.payload)}
            self.queue_trim_preview(hit.mode)
        else:
            self.drag = None
        self.draw_timeline()

    def on_canvas_drag(self, event) -> None:
        if not self.drag:
            return
        hit: Hit = self.drag["hit"]
        if hit.mode == "pan":
            self.canvas.scan_dragto(event.x, event.y, gain=1)
            return
        if hit.mode == "body":
            body_time = min(self.total_duration, self.from_x(self.canvas.canvasx(event.x)))
            self.playhead = self.snap_time(body_time, exclude_clip_idx=hit.index) if self.snap_allowed_for_event(event) else body_time
            self.draw_timeline()
            return
        row = self.timeline[hit.index]
        original = self.drag["row"]
        now = self.from_x(self.canvas.canvasx(event.x))
        delta = now - float(self.drag["start_time"])
        source_in = float(original.get("source_in", 0.0))
        source_out = float(original.get("source_out", source_in))
        output_duration = max(MIN_DURATION, float(original.get("output_duration", source_out - source_in)))
        speed = max(MIN_DURATION, (source_out - source_in) / output_duration)
        if hit.mode == "right":
            edge_time = float(original.get("output_out", 0.0)) + delta
            if self.snap_allowed_for_event(event):
                edge_time = self.snap_time(edge_time, exclude_clip_idx=hit.index)
            new_output_duration = max(MIN_DURATION, edge_time - float(original.get("output_in", 0.0)))
            new_source_out = source_in + new_output_duration * speed
            max_source_duration = self.source_duration_for_row(row)
            if max_source_duration > 0 and new_source_out > max_source_duration:
                new_source_out = max_source_duration
                new_output_duration = max(MIN_DURATION, (new_source_out - source_in) / speed)
            row["source_out"] = round(new_source_out, 6)
            row["output_duration"] = round(new_output_duration, 6)
        elif hit.mode == "left":
            edge_time = float(original.get("output_in", 0.0)) + delta
            if self.snap_allowed_for_event(event):
                edge_time = self.snap_time(edge_time, exclude_clip_idx=hit.index)
            new_output_duration = max(MIN_DURATION, float(original.get("output_out", 0.0)) - edge_time)
            new_source_in = source_out - new_output_duration * speed
            if new_source_in < 0:
                new_source_in = 0.0
                new_output_duration = max(MIN_DURATION, (source_out - new_source_in) / speed)
            row["source_in"] = round(new_source_in, 6)
            row["output_duration"] = round(new_output_duration, 6)
        self.recalculate_timeline()
        self.refresh_tree()
        self.refresh_inspector()
        self.queue_trim_preview(hit.mode)
        self.draw_timeline()

    def on_canvas_up(self, _event) -> None:
        if self.drag:
            hit: Hit = self.drag["hit"]
            if hit.mode != "pan":
                self.undo_stack.append(self.drag["snapshot"])
                if len(self.undo_stack) > self.max_history:
                    self.undo_stack = self.undo_stack[-self.max_history :]
                self.redo_stack.clear()
            self.drag = None
            self.update_history_buttons()
            if hit.mode != "pan":
                self.log("Timeline edit applied. Save Draft when ready.")

    def on_mousewheel(self, event) -> None:
        state = getattr(event, "state", 0)
        command_or_control = state & (0x0004 | 0x0010)
        shift = state & 0x0001
        if command_or_control:
            factor = 1.15 if event.delta > 0 else 0.87
            pointer_time = self.from_x(self.canvas.canvasx(event.x))
            self.zoom = max(0.4, min(12.0, self.zoom * factor))
            self.draw_timeline()
            self.scroll_to_time(pointer_time)
            return
        units = -1 if event.delta > 0 else 1
        self.canvas.xview_scroll(units * (10 if shift else 4), "units")

    def zoom_at_canvas_center(self, factor: float) -> None:
        if not hasattr(self, "canvas"):
            return
        center_time = self.from_x(self.canvas.canvasx(self.canvas.winfo_width() / 2))
        self.zoom = max(0.4, min(12.0, self.zoom * factor))
        self.draw_timeline()
        self.scroll_to_time(center_time)

    def on_root_configure(self, _event=None) -> None:
        if not hasattr(self, "root"):
            return
        if self.resize_job is not None:
            self.root.after_cancel(self.resize_job)
        self.resize_job = self.root.after(80, self.apply_responsive_layout)

    def apply_responsive_layout(self) -> None:
        self.resize_job = None
        if not hasattr(self, "viewer_canvas"):
            return
        root_w = max(900, self.root.winfo_width())
        root_h = max(600, self.root.winfo_height())
        viewer_h = max(260, min(430, int(root_h * 0.34)))
        trim_h = 128 if root_h < 760 else 168
        source_h = max(130, min(220, int(root_h * 0.19)))
        self.viewer_canvas.configure(height=viewer_h)
        if hasattr(self, "trim_canvas"):
            self.trim_canvas.configure(height=trim_h)
        if hasattr(self, "source_canvas"):
            self.source_canvas.configure(height=source_h)
        if hasattr(self, "main_paned"):
            left_w = 230 if root_w < 1180 else 286
            right_w = 280 if root_w < 1180 else 330
            try:
                self.main_paned.sashpos(0, left_w)
                self.main_paned.sashpos(1, max(left_w + 480, root_w - right_w))
            except tk.TclError:
                pass
        self.draw_timeline()

    def push_undo(self) -> None:
        self.undo_stack.append(copy.deepcopy(self.payload))
        if len(self.undo_stack) > self.max_history:
            self.undo_stack = self.undo_stack[-self.max_history :]
        self.redo_stack.clear()
        self.update_history_buttons()

    def update_history_buttons(self) -> None:
        if hasattr(self, "undo_button"):
            self.undo_button.configure(state=tk.NORMAL if self.undo_stack else tk.DISABLED)
        if hasattr(self, "redo_button"):
            self.redo_button.configure(state=tk.NORMAL if self.redo_stack else tk.DISABLED)

    def undo(self) -> None:
        if not self.undo_stack:
            self.log("Nothing to undo.")
            return
        self.redo_stack.append(copy.deepcopy(self.payload))
        if len(self.redo_stack) > self.max_history:
            self.redo_stack = self.redo_stack[-self.max_history :]
        self.payload = self.undo_stack.pop()
        self.recalculate_timeline()
        self.selected_index = min(self.selected_index or 0, max(0, len(self.timeline) - 1)) if self.timeline else None
        self.refresh_all()
        self.update_history_buttons()
        self.log("Undo applied.")

    def redo(self) -> None:
        if not self.redo_stack:
            self.log("Nothing to redo.")
            return
        self.undo_stack.append(copy.deepcopy(self.payload))
        if len(self.undo_stack) > self.max_history:
            self.undo_stack = self.undo_stack[-self.max_history :]
        self.payload = self.redo_stack.pop()
        self.recalculate_timeline()
        self.selected_index = min(self.selected_index or 0, max(0, len(self.timeline) - 1)) if self.timeline else None
        self.refresh_all()
        self.update_history_buttons()
        self.log("Redo applied.")

    def apply_fields(self) -> None:
        idx = self.selected_index
        if idx is None:
            return
        try:
            source_text = self.field_vars["source"].get().strip()
            source_in = max(0.0, self.parse_seconds_value(self.field_vars["source_in"].get()))
            source_out = max(source_in + MIN_DURATION, self.parse_seconds_value(self.field_vars["source_out"].get()))
            output_duration_text = self.field_vars["output_duration"].get().strip()
            speed_text = self.field_vars["speed"].get().strip()
            speed = self.parse_speed_value(speed_text) if speed_text else 0.0
            output_duration = max(MIN_DURATION, self.parse_seconds_value(output_duration_text)) if output_duration_text else 0.0
        except ValueError as exc:
            if hasattr(self, "root"):
                messagebox.showerror("Inspector", f"Could not parse a time or speed field: {exc}")
            return

        self.push_undo()
        row = self.timeline[idx]
        row["source"] = source_text
        max_source_duration = self.source_duration_for_row(row)
        if max_source_duration > 0:
            source_in = min(source_in, max(0.0, max_source_duration - MIN_DURATION))
            source_out = min(max_source_duration, max(source_in + MIN_DURATION, source_out))
        row["source_in"] = round(source_in, 6)
        row["source_out"] = round(source_out, 6)
        source_duration = max(MIN_DURATION, row["source_out"] - row["source_in"])
        if speed > 0:
            row["output_duration"] = round(source_duration / max(0.05, speed), 6)
        elif output_duration > 0:
            row["output_duration"] = round(output_duration, 6)
        grade = self.field_vars["grade"].get().strip()
        if grade:
            row["grade"] = grade
        elif "grade" in row:
            row.pop("grade")
        self.recalculate_timeline()
        self.refresh_all()
        self.log("Inspector fields applied.")

    def apply_note(self) -> None:
        idx = self.selected_index
        if idx is None:
            return
        self.push_undo()
        self.timeline[idx]["note"] = self.note_text.get("1.0", tk.END).strip()
        self.refresh_all()
        self.log("Note applied.")

    def move_selected(self, delta: int) -> None:
        idx = self.selected_index
        if idx is None:
            return
        new_idx = idx + delta
        if new_idx < 0 or new_idx >= len(self.timeline):
            self.log("Clip is already at that edge.")
            return
        self.push_undo()
        self.timeline[idx], self.timeline[new_idx] = self.timeline[new_idx], self.timeline[idx]
        self.selected_index = new_idx
        self.recalculate_timeline()
        self.playhead = float(self.timeline[new_idx].get("output_in", 0.0))
        self.refresh_all()
        self.log("Clip moved.")

    def duplicate_selected(self) -> None:
        idx = self.selected_index
        if idx is None or idx >= len(self.timeline):
            return
        self.push_undo()
        copied = copy.deepcopy(self.timeline[idx])
        base = str(copied.get("slot", f"clip_{idx + 1}"))
        copied["slot"] = f"{base}_copy"
        self.ensure_unique_clip_slots([copied])
        self.timeline.insert(idx + 1, copied)
        self.selected_index = idx + 1
        self.recalculate_timeline()
        self.playhead = float(self.timeline[self.selected_index].get("output_in", 0.0))
        self.refresh_all()
        self.log("Clip duplicated.")

    def clip_index_for_playhead_or_selected(self) -> int | None:
        if self.selected_index is not None and self.selected_index < len(self.timeline):
            row = self.timeline[self.selected_index]
            if float(row.get("output_in", 0.0)) <= self.playhead <= float(row.get("output_out", 0.0)):
                return self.selected_index
        active = self.active_clip_at_output(self.playhead)
        if active:
            return active[0]
        return self.selected_index

    def ripple_trim_to_playhead(self, side: str) -> None:
        idx = self.clip_index_for_playhead_or_selected()
        if idx is None or idx >= len(self.timeline):
            return
        row = self.timeline[idx]
        output_in = float(row.get("output_in", 0.0))
        output_out = float(row.get("output_out", 0.0))
        if not (output_in + MIN_DURATION < self.playhead < output_out - MIN_DURATION):
            self.log("Playhead must be inside the selected clip for ripple trim.")
            return
        source_time = self.source_time_for_output(row, self.playhead)
        self.push_undo()
        if side == "left":
            row["source_in"] = round(source_time, 6)
            row["output_duration"] = round(output_out - self.playhead, 6)
            message = "Ripple trim start to playhead."
        else:
            row["source_out"] = round(source_time, 6)
            row["output_duration"] = round(self.playhead - output_in, 6)
            message = "Ripple trim end to playhead."
        self.selected_index = idx
        self.recalculate_timeline()
        self.refresh_all()
        self.log(message)

    def jump_to_edit_point(self, direction: int) -> None:
        points = sorted({0.0, self.total_duration} | {float(row.get("output_in", 0.0)) for row in self.timeline} | {float(row.get("output_out", 0.0)) for row in self.timeline})
        if not points:
            return
        epsilon = 0.001
        if direction > 0:
            target = next((point for point in points if point > self.playhead + epsilon), points[-1])
        else:
            target = next((point for point in reversed(points) if point < self.playhead - epsilon), points[0])
        self.playhead = target
        active = self.active_clip_at_output(self.playhead)
        if active:
            self.selected_index = active[0]
        self.refresh_tree()
        self.refresh_inspector()
        self.draw_timeline()
        self.scroll_to_time(self.playhead)

    def fit_selected_to_section(self) -> None:
        idx = self.selected_index
        section_idx = self.current_section_index()
        if idx is None or idx >= len(self.timeline) or section_idx is None:
            self.log("Select a clip and load or select a section first.")
            return
        section = self.song_sections[section_idx]
        duration = max(MIN_DURATION, float(section.get("end", 0.0)) - float(section.get("start", 0.0)))
        self.push_undo()
        self.timeline[idx]["output_duration"] = round(duration, 6)
        self.recalculate_timeline()
        self.refresh_all()
        self.log(f"Clip fit to section {section.get('id', '')}: {duration:.2f}s")

    def set_speed_for_selected(self, speed: float) -> None:
        idx = self.selected_index
        if idx is None:
            return
        speed = max(0.05, float(speed))
        self.push_undo()
        row = self.timeline[idx]
        source_duration = max(MIN_DURATION, float(row.get("source_out", 0.0)) - float(row.get("source_in", 0.0)))
        row["output_duration"] = round(source_duration / speed, 6)
        self.recalculate_timeline()
        self.refresh_all()
        self.log(f"Speed set to {speed:.2f}x.")

    def split_selected(self) -> None:
        idx = self.selected_index
        if idx is None:
            return
        row = self.timeline[idx]
        output_in = float(row.get("output_in", 0.0))
        output_out = float(row.get("output_out", 0.0))
        split_at = self.playhead
        if split_at <= output_in + MIN_DURATION or split_at >= output_out - MIN_DURATION:
            split_at = (output_in + output_out) / 2
        left_dur = split_at - output_in
        right_dur = output_out - split_at
        source_in = float(row.get("source_in", 0.0))
        source_out = float(row.get("source_out", source_in))
        speed = max(MIN_DURATION, (source_out - source_in) / max(MIN_DURATION, output_out - output_in))
        source_mid = source_in + left_dur * speed
        self.push_undo()
        left = copy.deepcopy(row)
        right = copy.deepcopy(row)
        left["slot"] = f"{row.get('slot', f'clip_{idx + 1}')}_A"
        right["slot"] = f"{row.get('slot', f'clip_{idx + 1}')}_B"
        left["source_out"] = round(source_mid, 6)
        left["output_duration"] = round(left_dur, 6)
        right["source_in"] = round(source_mid, 6)
        right["output_duration"] = round(right_dur, 6)
        self.timeline[idx : idx + 1] = [left, right]
        self.selected_index = idx + 1
        self.recalculate_timeline()
        self.refresh_all()
        self.log("Clip split.")

    def delete_selected(self) -> None:
        idx = self.selected_index
        if idx is None:
            return
        self.push_undo()
        self.timeline.pop(idx)
        self.selected_index = min(idx, len(self.timeline) - 1) if self.timeline else None
        self.recalculate_timeline()
        self.refresh_all()
        self.log("Clip deleted.")

    def save_draft(self) -> None:
        if not self.recipe_path:
            return
        self.recalculate_timeline()
        out = self.recipe_path.with_name(f"{self.recipe_path.stem}.edit-desk-draft.yaml")
        out.write_text(yaml.safe_dump(self.payload, allow_unicode=True, sort_keys=False))
        self.log(f"Draft saved: {out.relative_to(REPO_ROOT) if out.is_relative_to(REPO_ROOT) else out}")

    def save_snapshot(self) -> None:
        if not self.payload:
            return
        snap_dir = REPO_ROOT / "tools/idol-edit-desk/snapshots"
        snap_dir.mkdir(parents=True, exist_ok=True)
        stem = self.recipe_path.stem if self.recipe_path else "recipe"
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        out = snap_dir / f"{stem}-{stamp}.yaml"
        out.write_text(yaml.safe_dump(self.payload, allow_unicode=True, sort_keys=False))
        self.log(f"Snapshot saved: {out.relative_to(REPO_ROOT)}")

    def audio_path(self) -> Path | None:
        value = self.payload.get("audio_path")
        if not value:
            return None
        path = Path(value)
        if path.is_absolute():
            return path
        return self.run_root / path

    def load_song_waveform(self) -> None:
        audio = self.audio_path()
        if not audio or not audio.exists():
            path = filedialog.askopenfilename(title="Open song/audio", initialdir=str(self.run_root), filetypes=[("Audio", "*.mp3 *.wav *.m4a *.aac"), ("All files", "*.*")])
            if not path:
                return
            audio = Path(path)
            self.payload["audio_path"] = str(audio.relative_to(self.run_root)) if self.is_under(audio, self.run_root) else str(audio)
        self.log("Loading waveform...")
        self.set_job_status("waveform loading")
        threading.Thread(target=self._load_waveform_worker, args=(audio,), daemon=True).start()

    def _load_waveform_worker(self, audio: Path) -> None:
        try:
            import librosa
            import numpy as np

            y, _sr = librosa.load(str(audio), sr=12000, mono=True)
            bins = 1800
            if len(y) == 0:
                peaks = []
            else:
                chunk = max(1, len(y) // bins)
                peaks = [float(np.max(np.abs(y[i : i + chunk]))) for i in range(0, len(y), chunk)]
            self.waveform = peaks
            self.root.after(0, lambda: (self.draw_timeline(), self.set_job_status("idle"), self.log(f"Waveform loaded: {audio.name}")))
        except Exception as exc:
            self.root.after(0, lambda: (self.set_job_status("idle"), messagebox.showerror("Waveform error", str(exc))))

    def load_or_compute_bpm(self) -> None:
        summary = self.find_bpm_summary()
        if summary:
            self.bpm_summary = summary
            self.update_bpm_label()
            self.draw_timeline()
            source = self.short_path(self.bpm_source) if self.bpm_source else "run docs"
            self.tabs.select(self.sections_tab)
            self.log(f"BPM loaded: {summary} ({source})")
            return
        candidates = []
        if self.recipe_path:
            candidates.append(self.recipe_path.parent / "audio-beat-onset-summary.json")
        candidates.append(self.run_root / "generations/video/qc/sync-workbench-v1/audio-beat-onset-summary.json")
        for path in candidates:
            if path.exists():
                self.load_bpm_json(path)
                return
        audio = self.audio_path()
        if not audio or not audio.exists():
            messagebox.showinfo("BPM", "Load a song first, or place audio-beat-onset-summary.json near the recipe.")
            return
        self.log("Calculating BPM...")
        self.set_job_status("BPM calculating")
        threading.Thread(target=self._compute_bpm_worker, args=(audio,), daemon=True).start()

    def load_bpm_json(self, path: Path) -> None:
        payload = json.loads(path.read_text())
        self.bpm_summary = self.extract_bpm_from_payload(payload) or "loaded"
        self.bpm_source = str(path)
        self.update_bpm_label()
        self.draw_timeline()
        self.log(f"BPM loaded: {self.bpm_summary} ({path.name})")

    def _compute_bpm_worker(self, audio: Path) -> None:
        try:
            import librosa

            y, sr = librosa.load(str(audio), sr=None, mono=True)
            import numpy as np

            tempo, _beat_frames = librosa.beat.beat_track(y=y, sr=sr, units="frames")
            tempo_value = float(np.atleast_1d(tempo)[0])
            self.bpm_summary = f"{tempo_value:.2f} BPM"
            self.bpm_source = str(audio)
            self.root.after(0, lambda: (self.update_bpm_label(), self.draw_timeline(), self.set_job_status("idle"), self.log(f"BPM calculated: {tempo_value:.2f} BPM")))
        except Exception as exc:
            self.root.after(0, lambda: (self.set_job_status("idle"), messagebox.showerror("BPM error", str(exc))))

    def open_lyrics(self) -> None:
        path = filedialog.askopenfilename(title="Open lyrics or cue text", initialdir=str(self.run_root), filetypes=[("Text/YAML/Markdown", "*.txt *.md *.yaml *.yml"), ("All files", "*.*")])
        if not path:
            return
        p = Path(path)
        text = p.read_text(errors="replace")
        self.lyrics_text.delete("1.0", tk.END)
        self.lyrics_text.insert("1.0", text)
        self.lyric_marks = self.extract_lyric_marks(text)
        self.tabs.select(self.lyrics_tab)
        self.draw_timeline()
        self.log(f"Lyrics loaded: {p.name}")

    def extract_lyric_marks(self, text: str) -> list[tuple[float, str]]:
        marks = []
        patterns = [
            re.compile(r"(?P<m>\d{1,2}):(?P<s>\d{2}(?:\.\d+)?)\s*(?P<label>.+)"),
            re.compile(r"(?P<s>\d+(?:\.\d+)?)s\s*[:|-]?\s*(?P<label>.+)"),
        ]
        for line in text.splitlines():
            stripped = line.strip()
            for pattern in patterns:
                match = pattern.search(stripped)
                if match:
                    minutes = float(match.groupdict().get("m") or 0)
                    seconds = float(match.group("s"))
                    marks.append((minutes * 60 + seconds, match.group("label").strip()))
                    break
        return marks

    def open_contact_sheet(self) -> None:
        if Image is None or ImageTk is None:
            messagebox.showerror("Contact Sheet", "Pillow is not available in this Python environment.")
            return
        path = filedialog.askopenfilename(title="Open contact sheet", initialdir=str(self.run_root), filetypes=[("Images", "*.png *.jpg *.jpeg *.webp"), ("All files", "*.*")])
        if not path:
            return
        img = Image.open(path)
        max_w = max(320, self.contact_canvas.winfo_width() - 20)
        max_h = max(480, self.contact_canvas.winfo_height() - 20)
        img.thumbnail((max_w, max_h))
        self.contact_image_ref = ImageTk.PhotoImage(img)
        self.contact_canvas.delete("all")
        self.contact_canvas.create_image(8, 8, anchor=tk.NW, image=self.contact_image_ref)
        self.tabs.select(self.contact_tab)
        self.log(f"Contact sheet loaded: {Path(path).name}")

    def render_preview(self) -> None:
        if not self.recipe_path:
            return
        idx = self.selected_index
        if idx is None:
            messagebox.showinfo("Preview", "Select a clip first.")
            return
        self.save_draft()
        draft = self.recipe_path.with_name(f"{self.recipe_path.stem}.edit-desk-draft.yaml")
        row = self.timeline[idx]
        start = max(0.0, float(row.get("output_in", 0.0)) - 1.0)
        end = min(self.total_duration, float(row.get("output_out", 0.0)) + 1.0)
        out_dir = self.run_root / "generations/video/qc/previews"
        out_dir.mkdir(parents=True, exist_ok=True)
        out = out_dir / f"edit-desk-{self.recipe_path.stem}-{start:.1f}-{end:.1f}.mp4"
        cmd = [
            str(REPO_ROOT / "scripts/idol-video-python"),
            str(REPO_ROOT / "scripts/idol_video_ffmpeg_revise_render.py"),
            "--run-root",
            str(self.run_root),
            "--recipe",
            str(draft),
            "--output",
            str(out),
            "--profile",
            "proxy",
            "--render-mode",
            "segments",
            "--preview-start",
            f"{start:.6f}",
            "--preview-end",
            f"{end:.6f}",
        ]
        self.log(f"Rendering preview {start:.1f}-{end:.1f}s...")
        self.set_job_status(f"render {start:.1f}-{end:.1f}s")
        threading.Thread(target=self._render_worker, args=(cmd, out), daemon=True).start()

    def _render_worker(self, cmd: list[str], out: Path) -> None:
        try:
            subprocess.run(cmd, cwd=REPO_ROOT, check=True, capture_output=True, text=True)
            self.last_preview_path = out
            self.root.after(0, lambda: (self.set_job_status("idle"), self.log(f"Preview ready: {out.relative_to(REPO_ROOT)}")))
        except subprocess.CalledProcessError as exc:
            detail = exc.stderr or exc.stdout or str(exc)
            self.root.after(0, lambda: (self.set_job_status("idle"), messagebox.showerror("Preview render failed", detail[-2000:])))

    def open_preview(self) -> None:
        if not self.last_preview_path or not self.last_preview_path.exists():
            messagebox.showinfo("Preview", "No preview render is ready yet.")
            return
        subprocess.Popen(["open", str(self.last_preview_path)])

    def reveal_source(self) -> None:
        idx = self.selected_index
        if idx is None or idx >= len(self.timeline):
            return
        source = self.resolve_source_path(self.timeline[idx].get("source", ""))
        if not source.exists():
            messagebox.showinfo("Reveal", "Source file is missing.")
            return
        subprocess.Popen(["open", "-R", str(source)])

    def open_terminal(self) -> None:
        path = self.run_root if self.run_root.exists() else REPO_ROOT
        try:
            subprocess.Popen(["open", "-a", "Terminal", str(path)])
            self.log(f"Terminal opening at: {self.short_path(path)}")
        except Exception as exc:
            messagebox.showerror("Terminal", str(exc))

    def short_path(self, value: str | Path) -> str:
        if value == "recipe":
            return "recipe"
        try:
            path = Path(value)
            if path.is_absolute():
                return str(path.relative_to(REPO_ROOT))
        except Exception:
            return str(value)
        return str(value)

    def is_under(self, path: Path, root: Path) -> bool:
        try:
            path.resolve().relative_to(root.resolve())
            return True
        except ValueError:
            return False

    def run(self) -> None:
        self.root.mainloop()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--recipe", type=Path)
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    app = EditDesk(recipe_path=args.recipe, smoke=args.smoke)
    if not args.smoke:
        app.run()


if __name__ == "__main__":
    main()
