import 'package:cinema_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

void main() {
  group('Seat model tests', () {
    test('Seat should serialize and deserialize correctly', () {
      final seat = Seat(
        type: SeatType.vip,
        row: 1,
        col: 2,
        status: SeatStatus.booked,
        isBroken: true,
      );

      final json = seat.toJson();
      final deserialized = Seat.fromJson(json);

      expect(deserialized.row, 1);
      expect(deserialized.col, 2);
      expect(deserialized.status, SeatStatus.booked);
      expect(deserialized.isBroken, true);
      expect(deserialized.type, SeatType.vip);
    });
  });

  group('Seat allocation logic tests', () {
    late List<List<Seat>> layout;

    setUp(() {
      layout = List.generate(
        3,
            (r) => List.generate(
          5,
              (c) => Seat(
            type: SeatType.regular,
            row: r,
            col: c,
          ),
        ),
      );
    });

    test('All seats should initially be free and not broken', () {
      for (var row in layout) {
        for (var seat in row) {
          expect(seat.status, SeatStatus.free);
          expect(seat.isBroken, false);
        }
      }
    });

    test('Booking a seat should mark it as booked', () {
      final seat = layout[0][0];
      seat.status = SeatStatus.booked;

      expect(seat.status, SeatStatus.booked);
    });

    test('Cannot allocate broken seat', () {
      final seat = layout[0][0];
      seat.isBroken = true;

      final canAllocate = !seat.isBroken && seat.status == SeatStatus.free;

      expect(canAllocate, false);
    });

    test('Should allocate consecutive free seats', () {
      int seatsRequested = 3;
      List<Seat> selectedSeats = [];

      for (int r = 0; r < layout.length; r++) {
        for (int c = 0; c <= layout[r].length - seatsRequested; c++) {
          var candidateSeats = layout[r].sublist(c, c + seatsRequested);

          if (candidateSeats.every((s) => !s.isBroken && s.status == SeatStatus.free)) {
            selectedSeats = candidateSeats;
            for (var seat in candidateSeats) {
              seat.status = SeatStatus.selected;
            }
            break;
          }
        }
        if (selectedSeats.isNotEmpty) break;
      }

      expect(selectedSeats.length, seatsRequested);
      for (var seat in selectedSeats) {
        expect(seat.status, SeatStatus.selected);
      }
    });
  });
}
