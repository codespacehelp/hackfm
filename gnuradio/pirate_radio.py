#!/usr/bin/env python3
# -*- coding: utf-8 -*-

#
# SPDX-License-Identifier: GPL-3.0
#
# GNU Radio Python Flow Graph
# Title: Pirate Radio
# GNU Radio version: 3.10.12.0

from PyQt5 import Qt
from gnuradio import qtgui
from gnuradio import analog
from gnuradio import blocks
from gnuradio import eng_notation
from gnuradio import filter
from gnuradio.filter import firdes
from gnuradio import gr
from gnuradio.fft import window
import sys
import signal
from PyQt5 import Qt
from argparse import ArgumentParser
from gnuradio.eng_arg import eng_float, intx
from gnuradio import soapy
import threading



class pirate_radio(gr.top_block, Qt.QWidget):

    def __init__(self):
        gr.top_block.__init__(self, "Pirate Radio", catch_exceptions=True)
        Qt.QWidget.__init__(self)
        self.setWindowTitle("Pirate Radio")
        qtgui.util.check_set_qss()
        try:
            self.setWindowIcon(Qt.QIcon.fromTheme('gnuradio-grc'))
        except BaseException as exc:
            print(f"Qt GUI: Could not set Icon: {str(exc)}", file=sys.stderr)
        self.top_scroll_layout = Qt.QVBoxLayout()
        self.setLayout(self.top_scroll_layout)
        self.top_scroll = Qt.QScrollArea()
        self.top_scroll.setFrameStyle(Qt.QFrame.NoFrame)
        self.top_scroll_layout.addWidget(self.top_scroll)
        self.top_scroll.setWidgetResizable(True)
        self.top_widget = Qt.QWidget()
        self.top_scroll.setWidget(self.top_widget)
        self.top_layout = Qt.QVBoxLayout(self.top_widget)
        self.top_grid_layout = Qt.QGridLayout()
        self.top_layout.addLayout(self.top_grid_layout)

        self.settings = Qt.QSettings("gnuradio/flowgraphs", "pirate_radio")

        try:
            geometry = self.settings.value("geometry")
            if geometry:
                self.restoreGeometry(geometry)
        except BaseException as exc:
            print(f"Qt GUI: Could not restore geometry: {str(exc)}", file=sys.stderr)
        self.flowgraph_started = threading.Event()

        ##################################################
        # Variables
        ##################################################
        self.rf_freq = rf_freq = 102.2e6
        self.transmit_status_label = transmit_status_label = str(rf_freq/1e6) + " MHz"
        self.rf_rate = rf_rate = 2_000_000
        self.quad_rate = quad_rate = 480_000
        self.audio_rate = audio_rate = 48_000

        ##################################################
        # Blocks
        ##################################################

        self._transmit_status_label_tool_bar = Qt.QToolBar(self)

        if None:
            self._transmit_status_label_formatter = None
        else:
            self._transmit_status_label_formatter = lambda x: str(x)

        self._transmit_status_label_tool_bar.addWidget(Qt.QLabel("Transmitting at"))
        self._transmit_status_label_label = Qt.QLabel(str(self._transmit_status_label_formatter(self.transmit_status_label)))
        self._transmit_status_label_tool_bar.addWidget(self._transmit_status_label_label)
        self.top_layout.addWidget(self._transmit_status_label_tool_bar)
        self.soapy_hackrf_sink_0 = None
        dev = 'driver=hackrf'
        stream_args = ''
        tune_args = ['']
        settings = ['']

        self.soapy_hackrf_sink_0 = soapy.sink(dev, "fc32", 1, '',
                                  stream_args, tune_args, settings)
        self.soapy_hackrf_sink_0.set_sample_rate(0, rf_rate)
        self.soapy_hackrf_sink_0.set_bandwidth(0, 0)
        self.soapy_hackrf_sink_0.set_frequency(0, rf_freq)
        self.soapy_hackrf_sink_0.set_gain(0, 'AMP', False)
        self.soapy_hackrf_sink_0.set_gain(0, 'VGA', min(max(16, 0.0), 47.0))
        self.rational_resampler_xxx_1 = filter.rational_resampler_ccc(
                interpolation=rf_rate,
                decimation=quad_rate,
                taps=[],
                fractional_bw=0)
        self.rational_resampler_xxx_0 = filter.rational_resampler_fff(
                interpolation=quad_rate,
                decimation=audio_rate,
                taps=[],
                fractional_bw=0)
        self.blocks_wavfile_source_0 = blocks.wavfile_source('audio/example_1mb.wav', True)
        self.analog_nbfm_tx_0 = analog.nbfm_tx(
        	audio_rate=quad_rate,
        	quad_rate=quad_rate,
        	tau=(75e-6),
        	max_dev=75_000,
        	fh=(-1.0),
                )


        ##################################################
        # Connections
        ##################################################
        self.connect((self.analog_nbfm_tx_0, 0), (self.rational_resampler_xxx_1, 0))
        self.connect((self.blocks_wavfile_source_0, 0), (self.rational_resampler_xxx_0, 0))
        self.connect((self.rational_resampler_xxx_0, 0), (self.analog_nbfm_tx_0, 0))
        self.connect((self.rational_resampler_xxx_1, 0), (self.soapy_hackrf_sink_0, 0))


    def closeEvent(self, event):
        self.settings = Qt.QSettings("gnuradio/flowgraphs", "pirate_radio")
        self.settings.setValue("geometry", self.saveGeometry())
        self.stop()
        self.wait()

        event.accept()

    def get_rf_freq(self):
        return self.rf_freq

    def set_rf_freq(self, rf_freq):
        self.rf_freq = rf_freq
        self.set_transmit_status_label(str(self.rf_freq/1e6) + " MHz")
        self.soapy_hackrf_sink_0.set_frequency(0, self.rf_freq)

    def get_transmit_status_label(self):
        return self.transmit_status_label

    def set_transmit_status_label(self, transmit_status_label):
        self.transmit_status_label = transmit_status_label
        Qt.QMetaObject.invokeMethod(self._transmit_status_label_label, "setText", Qt.Q_ARG("QString", str(self._transmit_status_label_formatter(self.transmit_status_label))))

    def get_rf_rate(self):
        return self.rf_rate

    def set_rf_rate(self, rf_rate):
        self.rf_rate = rf_rate
        self.soapy_hackrf_sink_0.set_sample_rate(0, self.rf_rate)

    def get_quad_rate(self):
        return self.quad_rate

    def set_quad_rate(self, quad_rate):
        self.quad_rate = quad_rate

    def get_audio_rate(self):
        return self.audio_rate

    def set_audio_rate(self, audio_rate):
        self.audio_rate = audio_rate




def main(top_block_cls=pirate_radio, options=None):

    qapp = Qt.QApplication(sys.argv)

    tb = top_block_cls()

    tb.start()
    tb.flowgraph_started.set()

    tb.show()

    def sig_handler(sig=None, frame=None):
        tb.stop()
        tb.wait()

        Qt.QApplication.quit()

    signal.signal(signal.SIGINT, sig_handler)
    signal.signal(signal.SIGTERM, sig_handler)

    timer = Qt.QTimer()
    timer.start(500)
    timer.timeout.connect(lambda: None)

    qapp.exec_()

if __name__ == '__main__':
    main()
