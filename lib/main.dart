
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft])
      .then((_) {
    runApp(const CinemaSeatingApp());
  });
}

class CinemaSeatingApp extends StatelessWidget {
  const CinemaSeatingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cinema Seating',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: CinemaSeatingPage(),
    );
  }
}

enum SeatStatus { free, booked, selected }
enum SeatType { regular, vip, accessible }

class Seat {
  SeatType type;
  SeatStatus status;
  bool isBroken;
  int row;
  int col;

  Seat({
    required this.type,
    this.status = SeatStatus.free,
    this.isBroken = false,
    required this.row,
    required this.col,
  });

  Map<String, dynamic> toJson() {
    return {
      'row': row,
      'col': col,
      'status': status.index,
      'isBroken': isBroken,
      'type': type.index,
    };
  }

  static Seat fromJson(Map<String, dynamic> json) {
    return Seat(
      row: json['row'],
      col: json['col'],
      status: SeatStatus.values[json['status']],
      isBroken: json['isBroken'],
      type: SeatType.values[json['type']],
    );
  }
}

class CinemaSeatingPage extends StatefulWidget {
  @override
  State<CinemaSeatingPage> createState() => _CinemaSeatingPageState();
}

class _CinemaSeatingPageState extends State<CinemaSeatingPage> {
  late List<List<Seat>> layout;
  bool adminOverride = false;
  String message = '';
  String userType = 'regular';
  int seatsRequested = 1;
  List<Seat> selectedSeats = [];
  int userAge = 30;
  final int elderlyAgeThreshold = 65;
  final List<int> ageRestrictedRows = [2, 3];

  static const String prefsKey = 'savedSeats';
  late TextEditingController ageController;


  @override
  void initState() {
    super.initState();
    ageController = TextEditingController(text: userAge.toString());
  ageController.addListener(() {
      final val = int.tryParse(ageController.text);
      if (val != null && val != userAge) {
        setState(() {
          userAge = val;
        });
      }
    });
    _initializeLayout();
  }

  Future<void> _initializeLayout() async {
    layout = List.generate(
      7,
          (r) => List.generate(10, (c) {
        SeatType type;
        if (r == 0) {
          type = SeatType.vip;
        } else if (r == 6) {
          type = SeatType.accessible;
        } else {
          type = SeatType.regular;
        }
        return Seat(type: type, row: r, col: c);
      }),
    );

    _markBrokenSeatsRandomly();

    await _loadSavedSeats();

    setState(() {
      selectedSeats.clear();
      message = '';
    });
  }

  void _markBrokenSeatsRandomly() {
    var rand = Random();
    int brokenCount = 0;
    while (brokenCount < 5) {
      int r = rand.nextInt(layout.length);
      int c = rand.nextInt(layout[0].length);
      var seat = layout[r][c];
      if (!seat.isBroken && seat.status == SeatStatus.free) {
        seat.isBroken = true;
        brokenCount++;
      }
    }
  }

  Future<void> _loadSavedSeats() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? savedSeatsJson = prefs.getString(prefsKey);
    if (savedSeatsJson == null) return;

    List<dynamic> savedSeatsList = jsonDecode(savedSeatsJson);
    for (var seatJson in savedSeatsList) {
      Seat savedSeat = Seat.fromJson(seatJson);
      if (savedSeat.status == SeatStatus.booked) {
        var seat = layout[savedSeat.row][savedSeat.col];
        seat.status = SeatStatus.booked;
        seat.isBroken = savedSeat.isBroken;
      }
    }
  }

  Future<void> _saveSeats() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> seatsToSave = [];
    for (var row in layout) {
      for (var seat in row) {
        if (seat.status == SeatStatus.booked ||
            seat.status == SeatStatus.free ||
            seat.status == SeatStatus.selected) {
          seatsToSave.add(seat.toJson());
        }
      }
    }
    String encoded = jsonEncode(seatsToSave);
    await prefs.setString(prefsKey, encoded);
  }

  void _resetLayout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
    setState(() {
      _initializeLayout();
      selectedSeats.clear();
      message = 'Layout reset and saved data cleared.';
      ageController.text = userAge.toString();

    });
  }

  void _cancelSeats() async {
    setState(() {
      for (var seat in selectedSeats) {
        seat.status = SeatStatus.free;
      }
      selectedSeats.clear();
      message = 'Seats cancelled and freed!';
    });
    await _saveSeats();
  }

  bool _canSeatChildAt(int row) {
    return !(ageRestrictedRows.contains(row) && userAge < elderlyAgeThreshold);
  }

  bool _canAllocateSeat(Seat seat) {
    if (seat.isBroken || seat.status != SeatStatus.free) return false;
    if (!_canSeatChildAt(seat.row) && userAge > 16) return false;
    if (userAge >= elderlyAgeThreshold) return true;

    switch (userType) {
      case 'vip':
        return seat.type == SeatType.vip;
      case 'accessible':
        return seat.type == SeatType.accessible;
      default:
        return seat.type == SeatType.regular;
    }
  }

  void _allocateSeats() async {
    setState(() {
      message = '';
      selectedSeats.clear();

      if (seatsRequested < 1 || seatsRequested > 7) {
        message = 'Request seats between 1 and 7';
        return;
      }

      if (adminOverride) {
        for (var row in layout) {
          for (var seat in row) {
            if (seat.status == SeatStatus.free && !seat.isBroken) {
              selectedSeats.add(seat);
              if (selectedSeats.length == seatsRequested) break;
            }
          }
          if (selectedSeats.length == seatsRequested) break;
        }
        if (selectedSeats.length == seatsRequested) {
          for (var seat in selectedSeats) seat.status = SeatStatus.selected;
          message = 'Seats allocated (Admin Override).';
        } else {
          message = 'Not enough free seats available.';
        }
        return;
      }

      bool allocated = false;
      for (int r = 0; r < layout.length; r++) {
        for (int c = 0; c <= layout[r].length - seatsRequested; c++) {
          var candidateSeats = layout[r].sublist(c, c + seatsRequested);
          if (candidateSeats.every((s) => _canAllocateSeat(s))) {
            for (var seat in candidateSeats) {
              seat.status = SeatStatus.selected;
              selectedSeats.add(seat);
            }
            allocated = true;
            break;
          }
        }
        if (allocated) break;
      }

      message = allocated
          ? 'Seats allocated successfully.'
          : 'No suitable block of seats available for your request.';
    });
  }

  void _confirmBooking() async {
    if (selectedSeats.isEmpty) {
      setState(() {
        message = 'No seats selected to book.';
      });
      return;
    }
    setState(() {
      for (var seat in selectedSeats) {
        seat.status = SeatStatus.booked;
      }
      selectedSeats.clear();
      message = 'Seats booked successfully.';
    });
    await _saveSeats();
  }

  Color _getSeatColor(Seat seat) {
    if (seat.isBroken) return Colors.red.shade700;
    if (seat.status == SeatStatus.booked) return Colors.grey.shade600;
    if (seat.status == SeatStatus.selected) return Colors.green.shade400;
    switch (seat.type) {
      case SeatType.vip:
        return Colors.purple.shade300;
      case SeatType.accessible:
        return Colors.orange.shade300;
      default:
        return Colors.blue.shade300;
    }
  }

  @override
  void dispose() {
    ageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    Widget _smallButton(String label, VoidCallback onPressed) {
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          minimumSize: const Size(60, 30),
          textStyle: const TextStyle(fontSize: 10),
        ),
        child: Text(label),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Cinema Seating Allocation')),
      body: SafeArea(
    child: Row(
      children: [
        Center(child:  Column(
          children: [
            // Controls
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('User Type:', style: TextStyle(fontSize: 12)),
                // DropdownButton<String>(
                //   value: userType,
                //   style: const TextStyle(fontSize: 12),
                //   items: const [
                //     DropdownMenuItem(value: 'regular', child: Text('Regular')),
                //     DropdownMenuItem(value: 'vip', child: Text('VIP')),
                //     DropdownMenuItem(value: 'accessible', child: Text('Accessible')),
                //   ],
                //   onChanged: (v) {
                //     setState(() {
                //       userType = v!;
                //       selectedSeats.clear();
                //       for (var row in layout) {
                //         for (var seat in row) {
                //           if (seat.status == SeatStatus.selected) {
                //             seat.status = SeatStatus.free;
                //           }
                //         }
                //       }
                //     });
                //   },
                // ),
                DropdownButton<String>(
                  value: userType,
                  items: const [
                    DropdownMenuItem(value: 'regular', child: Text('Regular')),
                    DropdownMenuItem(value: 'vip', child: Text('VIP')),
                    DropdownMenuItem(value: 'accessible', child: Text('Accessible')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        userType = val;
                        message = '';
                      });
                    }
                  },
                ),
                const Text('Seats:', style: TextStyle(fontSize: 12)),
                // DropdownButton<int>(
                //   value: seatsRequested,
                //   style: const TextStyle(fontSize: 12),
                //   items: List.generate(7, (i) => i + 1)
                //       .map((e) => DropdownMenuItem(value: e, child: Text('$e')))
                //       .toList(),
                //   onChanged: (v) {
                //     setState(() {
                //       seatsRequested = v!;
                //     });
                //   },
                // ),
                DropdownButton<int>(
                  value: seatsRequested,
                  items: List.generate(
                      7,
                          (i) => DropdownMenuItem(
                          value: i + 1, child: Text('${i + 1}'))),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        seatsRequested = val;
                        message = '';
                      });
                    }
                  },
                ),
                const Text('Age:', style: TextStyle(fontSize: 12)),
                SizedBox(
                  width: 60,
                  child: TextField(
                    onChanged: (val){
                      final vals = int.tryParse(val);
                      setState(() {
                        userAge =vals!;
                      });
                  },
                    controller: ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    ),
                  ),
                ),
                // SizedBox(
                //   width: 40,
                //   height: 30,
                //   child: TextField(
                //     onChanged: (val) {
                //       setState(() {
                //         userAge = int.tryParse(val) ?? 30;
                //       });
                //     },
                //     controller: TextEditingController(text: userAge.toString()),
                //     keyboardType: TextInputType.number,
                //     style: const TextStyle(fontSize: 12),
                //     decoration: const InputDecoration(
                //       border: OutlineInputBorder(),
                //       contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                //     ),
                //   ),
                // ),
                const Text('Admin:', style: TextStyle(fontSize: 12)),
                Switch(
                  value: adminOverride,
                  onChanged: (v) {
                    setState(() {
                      adminOverride = v;
                      message = '';
                      selectedSeats.clear();
                      for (var row in layout) {
                        for (var seat in row) {
                          if (seat.status == SeatStatus.selected) {
                            seat.status = SeatStatus.free;
                          }
                        }
                      }
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(fontSize: 12)),
            // Flexible(
            //   flex: 5,
            //   child: Padding(
            //     padding: const EdgeInsets.all(4.0),
            //     child: InteractiveViewer(
            //         boundaryMargin: const EdgeInsets.all(50),
            //         minScale: 0.5,
            //         maxScale: 3.0,
            //         child: _buildSeatGrid()
            //     ),
            //   ),
            // ),
            Flexible(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: InteractiveViewer(
                  boundaryMargin: const EdgeInsets.all(50),
                  minScale: 0.5,
                  maxScale: 3.0,
                  child: SingleChildScrollView(          // vertical scrolling
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(        // horizontal scrolling
                      scrollDirection: Axis.horizontal,
                      child: _buildSeatGrid(),
                    ),
                  ),
                ),
              ),
            ),

            // const SizedBox(height: 8),
            _buildLegend()
            /// Wrap seating area in Expanded + ScrollView

          ],
        ),),


        SizedBox(
          width: 120, // Give it a fixed width OR use Flexible/Expanded
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _smallButton('Allocate', _allocateSeats),
              _smallButton('Book', _confirmBooking),
              _smallButton('Cancel', _cancelSeats),
              _smallButton('Reset', _resetLayout),
            ],
          ),
        ),
      ],
    ),
    ),


    );
  }

  Widget _buildSeatGrid() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Screen representation
        Container(
          width: 500,
          height: 20,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
              color: Colors.black87, borderRadius: BorderRadius.circular(6)),
          alignment: Alignment.center,
          child: const Text('SCREEN',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
        ),
        for (int r = 0; r < layout.length; r++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 6),
                child: Text(String.fromCharCode(65 + r),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              ...List.generate(layout[r].length, (c) {
                Seat seat = layout[r][c];
                return GestureDetector(
                  onTap: () {
                    if (seat.isBroken) return;
                    setState(() {
                      if (seat.status == SeatStatus.free) {
                        seat.status = SeatStatus.selected;
                        selectedSeats.add(seat);
                      } else if (seat.status == SeatStatus.selected) {
                        seat.status = SeatStatus.free;
                        selectedSeats.remove(seat);
                      }
                      message = '';
                    });
                  },
                  child: Container(
                    margin:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _getSeatColor(seat),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black45, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          offset: const Offset(1, 1),
                          blurRadius: 3,
                        )
                      ],
                    ),
                    alignment: Alignment.center,
                    child: seat.isBroken
                        ? const Icon(Icons.block, size: 20, color: Colors.white)
                        : Text('${c + 1}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.black87)),
                  ),
                );
              }),
            ],
          ),
      ],
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 20,
      children: [
        _legendBox(Colors.blue.shade300, 'Regular'),
        _legendBox(Colors.purple.shade300, 'VIP'),
        _legendBox(Colors.orange.shade300, 'Accessible'),
        _legendBox(Colors.grey.shade600, 'Booked'),
        _legendBox(Colors.red.shade700, 'Broken'),
        _legendBox(Colors.green.shade400, 'Selected'),
      ],
    );
  }

  Widget _legendBox(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

// import 'dart:convert';
// import 'dart:math';
//
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:shared_preferences/shared_preferences.dart';
//
// void main() {
//   WidgetsFlutterBinding.ensureInitialized();
//   SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft])
//       .then((_) {
//     runApp(const CinemaSeatingApp());
//   });
// }
//
// class CinemaSeatingApp extends StatelessWidget {
//   const CinemaSeatingApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Cinema Seating',
//       theme: ThemeData(primarySwatch: Colors.blue),
//       home: CinemaSeatingPage(),
//     );
//   }
// }
//
// enum SeatStatus { free, booked, selected }
// enum SeatType { regular, vip, accessible }
//
// class Seat {
//   SeatType type;
//   SeatStatus status;
//   bool isBroken;
//   int row;
//   int col;
//
//   Seat({
//     required this.type,
//     this.status = SeatStatus.free,
//     this.isBroken = false,
//     required this.row,
//     required this.col,
//   });
//
//   Map<String, dynamic> toJson() {
//     return {
//       'row': row,
//       'col': col,
//       'status': status.index,
//       'isBroken': isBroken,
//       'type': type.index,
//     };
//   }
//
//   static Seat fromJson(Map<String, dynamic> json) {
//     return Seat(
//       row: json['row'],
//       col: json['col'],
//       status: SeatStatus.values[json['status']],
//       isBroken: json['isBroken'],
//       type: SeatType.values[json['type']],
//     );
//   }
// }
//
// class CinemaSeatingPage extends StatefulWidget {
//   @override
//   State<CinemaSeatingPage> createState() => _CinemaSeatingPageState();
// }
//
// class _CinemaSeatingPageState extends State<CinemaSeatingPage> {
//   late List<List<Seat>> layout;
//   bool adminOverride = false;
//   String message = '';
//   String userType = 'regular';
//   int seatsRequested = 1;
//   List<Seat> selectedSeats = [];
//   int userAge = 30;
//   final int elderlyAgeThreshold = 65;
//   final List<int> ageRestrictedRows = [2, 3];
//
//   static const String prefsKey = 'savedSeats';
//
//   late TextEditingController ageController;
//
//   @override
//   void initState() {
//     super.initState();
//     ageController = TextEditingController(text: userAge.toString());
//     ageController.addListener(() {
//       final val = int.tryParse(ageController.text);
//       if (val != null && val != userAge) {
//         setState(() {
//           userAge = val;
//         });
//       }
//     });
//     _initializeLayout();
//   }
//
//   @override
//   void dispose() {
//     ageController.dispose();
//     super.dispose();
//   }
//
//   Future<void> _initializeLayout() async {
//     layout = List.generate(
//       7,
//           (r) => List.generate(10, (c) {
//         SeatType type;
//         if (r == 0) {
//           type = SeatType.vip;
//         } else if (r == 6) {
//           type = SeatType.accessible;
//         } else {
//           type = SeatType.regular;
//         }
//         return Seat(type: type, row: r, col: c);
//       }),
//     );
//
//     _markBrokenSeatsRandomly();
//
//     await _loadSavedSeats();
//
//     setState(() {
//       selectedSeats.clear();
//       message = '';
//     });
//   }
//
//   void _markBrokenSeatsRandomly() {
//     var rand = Random();
//     int brokenCount = 0;
//     while (brokenCount < 5) {
//       int r = rand.nextInt(layout.length);
//       int c = rand.nextInt(layout[0].length);
//       var seat = layout[r][c];
//       if (!seat.isBroken && seat.status == SeatStatus.free) {
//         seat.isBroken = true;
//         brokenCount++;
//       }
//     }
//   }
//
//   Future<void> _loadSavedSeats() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     String? savedSeatsJson = prefs.getString(prefsKey);
//     if (savedSeatsJson == null) return;
//
//     List<dynamic> savedSeatsList = jsonDecode(savedSeatsJson);
//     for (var seatJson in savedSeatsList) {
//       Seat savedSeat = Seat.fromJson(seatJson);
//       if (savedSeat.status == SeatStatus.booked) {
//         var seat = layout[savedSeat.row][savedSeat.col];
//         seat.status = SeatStatus.booked;
//         seat.isBroken = savedSeat.isBroken;
//       }
//     }
//   }
//
//   Future<void> _saveSeats() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     List<Map<String, dynamic>> seatsToSave = [];
//     for (var row in layout) {
//       for (var seat in row) {
//         if (seat.status == SeatStatus.booked ||
//             seat.status == SeatStatus.free ||
//             seat.status == SeatStatus.selected) {
//           seatsToSave.add(seat.toJson());
//         }
//       }
//     }
//     String encoded = jsonEncode(seatsToSave);
//     await prefs.setString(prefsKey, encoded);
//   }
//
//   void _resetLayout() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.remove(prefsKey);
//     await _initializeLayout();
//     setState(() {
//       selectedSeats.clear();
//       message = 'Layout reset and saved data cleared.';
//       ageController.text = userAge.toString();
//     });
//   }
//
//   void _cancelSeats() async {
//     setState(() {
//       for (var seat in selectedSeats) {
//         seat.status = SeatStatus.free;
//       }
//       selectedSeats.clear();
//       message = 'Seats cancelled and freed!';
//     });
//     await _saveSeats();
//   }
//
//   bool _canSeatChildAt(int row) {
//     return !(ageRestrictedRows.contains(row) && userAge < elderlyAgeThreshold);
//   }
//
//   bool _canAllocateSeat(Seat seat) {
//     if (seat.isBroken || seat.status != SeatStatus.free) return false;
//     if (!_canSeatChildAt(seat.row)) return false;
//     if (userAge >= elderlyAgeThreshold) return true;
//
//     switch (userType) {
//       case 'vip':
//         return seat.type == SeatType.vip;
//       case 'accessible':
//         return seat.type == SeatType.accessible;
//       default:
//         return seat.type == SeatType.regular;
//     }
//   }
//
//   void _allocateSeats() async {
//     setState(() {
//       message = '';
//       selectedSeats.clear();
//
//       if (seatsRequested < 1 || seatsRequested > 7) {
//         message = 'Request seats between 1 and 7';
//         return;
//       }
//
//       if (adminOverride) {
//         for (var row in layout) {
//           for (var seat in row) {
//             if (seat.status == SeatStatus.free && !seat.isBroken) {
//               selectedSeats.add(seat);
//               if (selectedSeats.length == seatsRequested) break;
//             }
//           }
//           if (selectedSeats.length == seatsRequested) break;
//         }
//         if (selectedSeats.length == seatsRequested) {
//           for (var seat in selectedSeats) seat.status = SeatStatus.selected;
//           message = 'Seats allocated (Admin Override).';
//         } else {
//           message = 'Not enough free seats available.';
//         }
//         return;
//       }
//
//       bool allocated = false;
//       for (int r = 0; r < layout.length; r++) {
//         for (int c = 0; c <= layout[r].length - seatsRequested; c++) {
//           var candidateSeats = layout[r].sublist(c, c + seatsRequested);
//           if (candidateSeats.every((s) => _canAllocateSeat(s))) {
//             for (var seat in candidateSeats) {
//               seat.status = SeatStatus.selected;
//               selectedSeats.add(seat);
//             }
//             allocated = true;
//             break;
//           }
//         }
//         if (allocated) break;
//       }
//
//       message = allocated
//           ? 'Seats allocated successfully.'
//           : 'No suitable block of seats available for your request.';
//     });
//   }
//
//   void _confirmBooking() async {
//     if (selectedSeats.isEmpty) {
//       setState(() {
//         message = 'No seats selected to book.';
//       });
//       return;
//     }
//     setState(() {
//       for (var seat in selectedSeats) {
//         seat.status = SeatStatus.booked;
//       }
//       selectedSeats.clear();
//       message = 'Seats booked successfully.';
//     });
//     await _saveSeats();
//   }
//
//   Color _getSeatColor(Seat seat) {
//     if (seat.isBroken) return Colors.red.shade700;
//     if (seat.status == SeatStatus.booked) return Colors.grey.shade600;
//     if (seat.status == SeatStatus.selected) return Colors.green.shade400;
//     switch (seat.type) {
//       case SeatType.vip:
//         return Colors.purple.shade300;
//       case SeatType.accessible:
//         return Colors.orange.shade300;
//       default:
//         return Colors.blue.shade300;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     Widget _smallButton(String label, VoidCallback onPressed) {
//       return ElevatedButton(
//         onPressed: onPressed,
//         style: ElevatedButton.styleFrom(
//           padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
//           minimumSize: const Size(60, 30),
//           textStyle: const TextStyle(fontSize: 10),
//         ),
//         child: Text(label),
//       );
//     }
//
//     return Scaffold(
//       appBar: AppBar(title: const Text('Cinema Seating Allocation')),
//       body: Padding(
//         padding: const EdgeInsets.all(8.0),
//         child: Column(children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               const Text('User Type:'),
//               const SizedBox(width: 10),
//               DropdownButton<String>(
//                 value: userType,
//                 items: const [
//                   DropdownMenuItem(value: 'regular', child: Text('Regular')),
//                   DropdownMenuItem(value: 'vip', child: Text('VIP')),
//                   DropdownMenuItem(value: 'accessible', child: Text('Accessible')),
//                 ],
//                 onChanged: (val) {
//                   if (val != null) {
//                     setState(() {
//                       userType = val;
//                       message = '';
//                     });
//                   }
//                 },
//               ),
//               const SizedBox(width: 20),
//               const Text('Age:'),
//               const SizedBox(width: 5),
//               SizedBox(
//                 width: 60,
//                 child: TextField(
//                   controller: ageController,
//                   keyboardType: TextInputType.number,
//                   decoration: const InputDecoration(
//                     border: OutlineInputBorder(),
//                     isDense: true,
//                     contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
//                   ),
//                 ),
//               ),
//               const SizedBox(width: 20),
//               const Text('Seats:'),
//               const SizedBox(width: 5),
//               DropdownButton<int>(
//                 value: seatsRequested,
//                 items: List.generate(
//                     7,
//                         (i) => DropdownMenuItem(
//                         value: i + 1, child: Text('${i + 1}'))),
//                 onChanged: (val) {
//                   if (val != null) {
//                     setState(() {
//                       seatsRequested = val;
//                       message = '';
//                     });
//                   }
//                 },
//               ),
//               const SizedBox(width: 20),
//               Row(
//                 children: [
//                   const Text('Admin Override'),
//                   Switch(
//                     value: adminOverride,
//                     onChanged: (val) {
//                       setState(() {
//                         adminOverride = val;
//                         message = '';
//                       });
//                     },
//                   ),
//                 ],
//               ),
//             ],
//           ),
//           const SizedBox(height: 10),
//           Expanded(
//             child: LayoutBuilder(
//               builder: (context, constraints) {
//                 double seatSize = min(28, (constraints.maxWidth - 20) / 10 - 4);
//
//                 return SingleChildScrollView(
//                   scrollDirection: Axis.vertical,
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: List.generate(layout.length, (r) {
//                       return Row(
//                         mainAxisAlignment: MainAxisAlignment.center,
//                         children: List.generate(layout[r].length, (c) {
//                           var seat = layout[r][c];
//                           return GestureDetector(
//                             onTap: () {
//                               if (seat.isBroken || seat.status == SeatStatus.booked) return;
//                               setState(() {
//                                 if (seat.status == SeatStatus.free) {
//                                   if (!adminOverride && !_canAllocateSeat(seat)) {
//                                     message = 'Seat not available for your user type or age.';
//                                     return;
//                                   }
//                                   if (selectedSeats.length >= seatsRequested) {
//                                     message =
//                                     'You have already selected $seatsRequested seats.';
//                                     return;
//                                   }
//                                   seat.status = SeatStatus.selected;
//                                   selectedSeats.add(seat);
//                                   message = '';
//                                 } else if (seat.status == SeatStatus.selected) {
//                                   seat.status = SeatStatus.free;
//                                   selectedSeats.removeWhere(
//                                           (s) => s.row == seat.row && s.col == seat.col);
//                                   message = '';
//                                 }
//                               });
//                             },
//                             child: Container(
//                               margin: const EdgeInsets.all(2),
//                               width: seatSize,
//                               height: seatSize,
//                               decoration: BoxDecoration(
//                                 color: _getSeatColor(seat),
//                                 borderRadius: BorderRadius.circular(4),
//                                 border: Border.all(color: Colors.black54),
//                               ),
//                               alignment: Alignment.center,
//                               child: Text(
//                                 '${seat.col + 1}',
//                                 style: const TextStyle(
//                                     fontSize: 12,
//                                     fontWeight: FontWeight.bold,
//                                     color: Colors.black87),
//                               ),
//                             ),
//                           );
//                         }),
//                       );
//                     }),
//                   ),
//                 );
//               },
//             ),
//           ),
//           const SizedBox(height: 10),
//           Wrap(
//             spacing: 10,
//             children: [
//               _smallButton('Allocate Seats', _allocateSeats),
//               _smallButton('Confirm Booking', _confirmBooking),
//               _smallButton('Cancel Selected', _cancelSeats),
//               _smallButton('Reset Layout', _resetLayout),
//             ],
//           ),
//           const SizedBox(height: 10),
//           Text(
//             message,
//             style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
//           ),
//         ]),
//       ),
//     );
//   }
// }
