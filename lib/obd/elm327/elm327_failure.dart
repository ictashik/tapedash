/// Why a command did not get an answer (CLAUDE.md 8.1).
///
/// Everything above the ELM327 layer deals in these, never in the adapter's
/// text: the main UI never shows a raw ELM error.
enum Elm327Failure {
  /// `NO DATA`: the car did not answer within the adapter's timeout. The PID
  /// may not be supported, the ECU may be asleep, or the answer was lost.
  noData,

  /// `?`: the adapter did not understand the command.
  unknownCommand,

  /// `STOPPED`: the adapter was interrupted, for instance by a command sent
  /// before the last one had its prompt.
  stopped,

  /// `CAN ERROR`: the adapter could not send or receive on the CAN bus. Often
  /// the ignition is off, or the protocol is wrong.
  canError,

  /// `BUS INIT: ...ERROR`: a K-line protocol could not start a conversation.
  busInitError,

  /// `UNABLE TO CONNECT`: the search for a protocol found nothing. Usually the
  /// ignition is off.
  unableToConnect,

  /// `BUFFER FULL`: the adapter's buffer overflowed and data was lost.
  bufferFull,

  /// `BUS BUSY`: too much traffic on the bus to send a message.
  busBusy,

  /// `BUS ERROR`: an invalid signal on the bus, most often a wiring problem.
  busError,

  /// `DATA ERROR` or `<DATA ERROR`: the car answered, but the answer was
  /// damaged or could not be read.
  dataError,

  /// `<RX ERROR`: an error in the CAN data received.
  rxError,

  /// `FB ERROR`: the adapter's own output was not seen on the bus.
  feedbackError,

  /// `LV RESET`: the adapter reset itself after a drop in its supply voltage,
  /// and has forgotten every setting.
  lowVoltageReset,

  /// `ERRnn`: an internal error of the adapter.
  internalError,

  /// Nothing came back in time, or what came back had no prompt.
  timeout,

  /// The link to the adapter went while the command was waiting.
  disconnected,

  /// An answer arrived, and could not be read: a byte that is not hex where
  /// data should be, a multi-frame message that stops short, or noise.
  garbled,
}
