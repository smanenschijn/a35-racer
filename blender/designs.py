"""
Car designs for carbuilder.py. All cars are fictional parodies of 80s/90s classics.

Curves are lists of (t, value) with t = 0 at the nose and 1 at the tail (metres for values):
  width     half width of the body
  top       height of the body top (bonnet, beltline, boot)
  bottom    height of the underside (wheel arches are cut out automatically)
  shoulder  height of the shoulder crease along the side
  roof_h    cabin height above the body top; its first/last t are where the glasshouse starts/ends
  roof_w    half width of the roof

Style keys: front (popup/rect/slim/twin_rect/round/square), grille (slats/band/egg), rear
(round4/oval2/bar/blocks/tall), spoiler (wing/hoop/roof/lip), bumper (body/black/chrome),
exhaust (dual/single/can/split), wheel_style (tenspoke/fivespoke/mesh/turbine/steel).
"""


def rgb(hex_color):
    """sRGB hex -> linear RGB for Blender materials."""
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(lin((hex_color >> s) & 255) for s in (16, 8, 0))


DESIGNS = {
    # Mazdo RX-Zeven: the player. Low wedge, pop-ups, big wing.
    'rx7': dict(
        root='RX7', length=4.30, wheel_r=0.31, wheel_w=0.225, track=0.735, front_axle=0.88, wheelbase=2.42,
        width=[(0, 0.62), (0.025, 0.78), (0.07, 0.855), (0.20, 0.895), (0.35, 0.885), (0.5, 0.878), (0.65, 0.888),
               (0.77, 0.898), (0.9, 0.878), (0.975, 0.84), (1.0, 0.80)],
        top=[(0, 0.47), (0.03, 0.585), (0.10, 0.665), (0.20, 0.715), (0.30, 0.75), (0.37, 0.772), (0.45, 0.80),
             (0.70, 0.83), (0.80, 0.865), (0.90, 0.895), (0.965, 0.90), (1.0, 0.85)],
        bottom=[(0, 0.24), (0.05, 0.17), (0.9, 0.17), (1.0, 0.29)],
        shoulder=[(0, 0.40), (0.08, 0.57), (0.3, 0.645), (0.6, 0.685), (0.85, 0.755), (1.0, 0.74)],
        roof_h=[(0.36, 0.0), (0.375, 0.07), (0.49, 0.40), (0.56, 0.425), (0.63, 0.41), (0.70, 0.31), (0.79, 0.05),
                (0.81, 0.0)],
        roof_w=[(0.36, 0.74), (0.42, 0.68), (0.50, 0.60), (0.62, 0.60), (0.72, 0.64), (0.81, 0.72)],
        paint=rgb(0xd81e1e), seat=(0.25, 0.02, 0.02),
        front='popup', rear='round4', spoiler='wing', bumper='body', exhaust='dual', wheel_style='tenspoke',
        extras=['vents', 'foglamps', 'splitter', 'diffuser', 'skirts', 'antenna'],
    ),

    # Toyoda Supremo (Sanne): long, muscular, hoop wing, oval tail lights.
    'supremo': dict(
        root='Supremo', length=4.52, wheel_r=0.32, wheel_w=0.235, track=0.75, front_axle=0.92, wheelbase=2.55,
        width=[(0, 0.64), (0.025, 0.79), (0.07, 0.86), (0.2, 0.905), (0.35, 0.895), (0.5, 0.885), (0.65, 0.9),
               (0.78, 0.912), (0.9, 0.89), (0.975, 0.85), (1, 0.82)],
        top=[(0, 0.52), (0.03, 0.62), (0.1, 0.69), (0.2, 0.73), (0.3, 0.76), (0.38, 0.785), (0.45, 0.81),
             (0.7, 0.84), (0.8, 0.87), (0.9, 0.9), (0.965, 0.905), (1, 0.86)],
        bottom=[(0, 0.25), (0.05, 0.17), (0.9, 0.17), (1, 0.3)],
        shoulder=[(0, 0.42), (0.08, 0.58), (0.3, 0.65), (0.6, 0.69), (0.85, 0.76), (1, 0.75)],
        roof_h=[(0.38, 0), (0.395, 0.07), (0.5, 0.41), (0.58, 0.43), (0.66, 0.4), (0.75, 0.24), (0.835, 0.04),
                (0.845, 0)],
        roof_w=[(0.38, 0.74), (0.44, 0.68), (0.52, 0.6), (0.64, 0.6), (0.74, 0.65), (0.845, 0.73)],
        glass=dict(ws_end=0.5, roof_end=0.66, rear_end=0.82, side0=0.44, side1=0.72),
        splits=dict(cowl=0.39, door_r=0.66, deck=0.845, tail=0.94),
        paint=rgb(0xf2c014), seat=(0.05, 0.05, 0.05),
        front='rect', rear='oval2', spoiler='hoop', bumper='body', exhaust='dual', wheel_style='fivespoke',
        extras=['foglamps', 'skirts'],
    ),

    # Wolfsburg Golv G60 (Henk-Jan): boxy 3-door hatch, round lamps in a black band, red stripe, BBS-style rims.
    'golv': dict(
        root='Golv', length=4.0, wheel_r=0.29, wheel_w=0.2, track=0.72, front_axle=0.80, wheelbase=2.47,
        width=[(0, 0.80), (0.02, 0.84), (0.06, 0.86), (0.5, 0.86), (0.94, 0.86), (0.98, 0.84), (1, 0.82)],
        top=[(0, 0.74), (0.02, 0.77), (0.1, 0.80), (0.25, 0.83), (0.30, 0.85), (0.5, 0.88), (0.95, 0.92),
             (0.99, 0.92), (1, 0.9)],
        bottom=[(0, 0.22), (0.05, 0.2), (0.95, 0.2), (1, 0.24)],
        shoulder=[(0, 0.66), (0.1, 0.68), (0.5, 0.73), (1, 0.76)],
        roof_h=[(0.30, 0), (0.315, 0.08), (0.42, 0.46), (0.50, 0.49), (0.78, 0.48), (0.90, 0.34), (0.975, 0.1),
                (0.99, 0)],
        roof_w=[(0.30, 0.74), (0.40, 0.68), (0.5, 0.64), (0.9, 0.64), (0.99, 0.70)],
        glass=dict(ws_end=0.42, roof_end=0.82, rear_end=0.98, side0=0.33, side1=0.72, pillars=[(0.585, 0.615)]),
        splits=dict(nose=0.05, cowl=0.31, door_r=0.62, deck=0.999, tail=0.955),
        top_inset=0.08,
        paint=rgb(0x1d4fd8), seat=(0.22, 0.03, 0.03),
        front='round', grille='band', grille_stripe=True, rear='blocks', spoiler='roof', bumper='black',
        exhaust='single', wheel_style='mesh', rear_seat=True, extras=['rubbing_strip'],
    ),

    # Hondo Civik (Joost): sloping hatch, light bar at the back, a big tuner exhaust.
    'civik': dict(
        root='Civik', length=4.1, wheel_r=0.29, wheel_w=0.2, track=0.72, front_axle=0.86, wheelbase=2.57,
        width=[(0, 0.66), (0.025, 0.79), (0.07, 0.84), (0.3, 0.85), (0.6, 0.85), (0.9, 0.84), (0.97, 0.81),
               (1, 0.78)],
        top=[(0, 0.56), (0.03, 0.64), (0.1, 0.70), (0.2, 0.74), (0.33, 0.79), (0.5, 0.84), (0.8, 0.89),
             (0.95, 0.92), (0.99, 0.92), (1, 0.88)],
        bottom=[(0, 0.24), (0.05, 0.18), (0.92, 0.18), (1, 0.28)],
        shoulder=[(0, 0.45), (0.1, 0.6), (0.5, 0.69), (1, 0.78)],
        roof_h=[(0.33, 0), (0.345, 0.07), (0.46, 0.44), (0.55, 0.46), (0.70, 0.43), (0.85, 0.30), (0.965, 0.08),
                (0.975, 0)],
        roof_w=[(0.33, 0.72), (0.42, 0.66), (0.52, 0.6), (0.75, 0.6), (0.975, 0.68)],
        glass=dict(ws_end=0.46, roof_end=0.74, rear_end=0.965, side0=0.36, side1=0.84, pillars=[(0.63, 0.655)]),
        splits=dict(nose=0.06, cowl=0.34, door_r=0.63, deck=0.999, tail=0.95),
        paint=rgb(0x8fd3ff), seat=(0.05, 0.05, 0.06),
        front='rect', rear='bar', spoiler='roof', bumper='body', exhaust='can', wheel_style='fivespoke',
        rear_seat=True, extras=['skirts'],
    ),

    # Opal Corso (Mehmet): tiny upright hatch, black bumpers, steel wheels, Thuisbesteld roof box.
    'corso': dict(
        root='Corso', length=3.9, wheel_r=0.28, wheel_w=0.185, track=0.70, front_axle=0.74, wheelbase=2.44,
        width=[(0, 0.76), (0.02, 0.80), (0.06, 0.83), (0.5, 0.83), (0.94, 0.83), (0.98, 0.81), (1, 0.79)],
        top=[(0, 0.70), (0.02, 0.74), (0.1, 0.78), (0.28, 0.86), (0.5, 0.9), (0.95, 0.92), (0.99, 0.92), (1, 0.9)],
        bottom=[(0, 0.22), (0.05, 0.2), (0.95, 0.2), (1, 0.24)],
        shoulder=[(0, 0.62), (0.1, 0.66), (0.5, 0.72), (1, 0.75)],
        roof_h=[(0.28, 0), (0.295, 0.08), (0.40, 0.47), (0.48, 0.50), (0.80, 0.49), (0.91, 0.34), (0.98, 0.08),
                (0.99, 0)],
        roof_w=[(0.28, 0.72), (0.38, 0.66), (0.48, 0.62), (0.9, 0.62), (0.99, 0.68)],
        glass=dict(ws_end=0.40, roof_end=0.83, rear_end=0.98, side0=0.31, side1=0.74, pillars=[(0.585, 0.61)]),
        splits=dict(nose=0.05, cowl=0.29, door_r=0.6, deck=0.999, tail=0.955),
        top_inset=0.09,
        paint=rgb(0xff6a00), seat=(0.08, 0.08, 0.09),
        front='twin_rect', grille='slats', rear='blocks', bumper='black', exhaust='single', wheel_style='steel',
        rear_seat=True, red_calipers=False, extras=['roofbox', 'rubbing_strip'],
    ),

    # Opal Calibro (Bennie): sleek black wedge with white stripes, turbine wheels, slim lamps.
    'calibro': dict(
        root='Calibro', length=4.5, wheel_r=0.30, wheel_w=0.215, track=0.74, front_axle=0.92, wheelbase=2.6,
        width=[(0, 0.62), (0.025, 0.78), (0.07, 0.85), (0.2, 0.88), (0.5, 0.875), (0.8, 0.885), (0.95, 0.86),
               (1, 0.82)],
        top=[(0, 0.48), (0.03, 0.58), (0.1, 0.65), (0.2, 0.70), (0.3, 0.74), (0.40, 0.775), (0.5, 0.80),
             (0.75, 0.84), (0.9, 0.9), (0.97, 0.91), (1, 0.87)],
        bottom=[(0, 0.23), (0.05, 0.17), (0.92, 0.17), (1, 0.28)],
        shoulder=[(0, 0.4), (0.1, 0.57), (0.4, 0.65), (0.8, 0.74), (1, 0.76)],
        roof_h=[(0.40, 0), (0.415, 0.06), (0.52, 0.39), (0.60, 0.41), (0.68, 0.38), (0.78, 0.22), (0.865, 0.04),
                (0.875, 0)],
        roof_w=[(0.40, 0.72), (0.46, 0.66), (0.54, 0.58), (0.66, 0.58), (0.76, 0.62), (0.875, 0.7)],
        glass=dict(ws_end=0.52, roof_end=0.68, rear_end=0.86, side0=0.44, side1=0.76),
        splits=dict(nose=0.07, cowl=0.41, door_r=0.67, deck=0.875, tail=0.95),
        paint=rgb(0x111111), stripe=(0.9, 0.9, 0.9), seat=(0.05, 0.05, 0.05),
        front='slim', rear='bar', spoiler='lip', bumper='body', exhaust='dual', wheel_style='turbine',
        extras=['stripes', 'skirts'],
    ),

    # Volvi 240 Kombi (Gerrit): the brick. Upright, long roof, chrome bumpers, egg-crate grille, hubcaps.
    'volvi': dict(
        root='Volvi', length=4.8, wheel_r=0.31, wheel_w=0.195, track=0.74, front_axle=0.93, wheelbase=2.64,
        width=[(0, 0.83), (0.015, 0.86), (0.04, 0.875), (0.96, 0.875), (0.985, 0.86), (1, 0.84)],
        top=[(0, 0.80), (0.015, 0.82), (0.05, 0.83), (0.25, 0.86), (0.27, 0.87), (0.5, 0.90), (0.97, 0.92),
             (0.995, 0.92), (1, 0.9)],
        bottom=[(0, 0.23), (0.04, 0.21), (0.96, 0.21), (1, 0.24)],
        shoulder=[(0, 0.72), (0.1, 0.74), (0.5, 0.76), (1, 0.78)],
        roof_h=[(0.27, 0), (0.29, 0.12), (0.37, 0.50), (0.42, 0.53), (0.96, 0.52), (0.985, 0.36), (0.995, 0.06),
                (1.0, 0)],
        roof_w=[(0.27, 0.76), (0.35, 0.72), (0.42, 0.7), (0.97, 0.7), (1.0, 0.72)],
        glass=dict(ws_end=0.37, roof_end=0.985, rear_end=1.0, side0=0.30, side1=0.965,
                   pillars=[(0.545, 0.565), (0.79, 0.815)]),
        splits=dict(nose=0.04, cowl=0.28, door_r=0.55, deck=0.999, tail=0.965),
        top_inset=0.06,
        paint=rgb(0x24563a), seat=(0.18, 0.1, 0.05),
        front='square', grille='egg', rear='tall', bumper='chrome', exhaust='single', wheel_style='steel',
        rear_seat=True, red_calipers=False, extras=['rails', 'antenna', 'rubbing_strip'],
    ),

    # Mitsubushi Space Wagen (Tante Riek): tall MPV with a sloping nose and roof rails.
    'spacewagen': dict(
        root='SpaceWagen', length=4.6, wheel_r=0.31, wheel_w=0.2, track=0.74, front_axle=0.85, wheelbase=2.72,
        width=[(0, 0.74), (0.03, 0.82), (0.08, 0.86), (0.5, 0.87), (0.95, 0.86), (0.99, 0.84), (1, 0.82)],
        top=[(0, 0.66), (0.03, 0.72), (0.1, 0.8), (0.2, 0.88), (0.25, 0.93), (0.5, 0.97), (0.97, 0.99), (1, 0.96)],
        bottom=[(0, 0.24), (0.05, 0.2), (0.95, 0.2), (1, 0.26)],
        shoulder=[(0, 0.55), (0.1, 0.68), (0.3, 0.82), (0.6, 0.86), (1, 0.88)],
        roof_h=[(0.25, 0), (0.27, 0.12), (0.40, 0.58), (0.46, 0.62), (0.94, 0.61), (0.975, 0.4), (0.992, 0.06),
                (1.0, 0)],
        roof_w=[(0.25, 0.74), (0.36, 0.7), (0.46, 0.68), (0.95, 0.68), (1, 0.7)],
        glass=dict(ws_end=0.40, roof_end=0.97, rear_end=1.0, side0=0.28, side1=0.965,
                   pillars=[(0.50, 0.52), (0.72, 0.745)]),
        splits=dict(nose=0.05, cowl=0.26, door_r=0.5, deck=0.999, tail=0.96),
        paint=rgb(0xb03a7a), seat=(0.12, 0.12, 0.13), seat_z=0.12,
        front='twin_rect', grille='slats', chrome_grille=True, rear='tall', bumper='body', exhaust='single',
        wheel_style='steel', rear_seat=True, red_calipers=False, extras=['rails', 'rubbing_strip'],
    ),

    # ---- Traffic and police (simpler: steel wheels, few extras) -------------------------------

    # Opal Vectro: plain four-door saloon.
    'tr_sedan': dict(
        root='TrSedan', lod=True, length=4.5, wheel_r=0.30, wheel_w=0.195, track=0.74, front_axle=0.9, wheelbase=2.65,
        width=[(0, 0.74), (0.03, 0.83), (0.08, 0.87), (0.5, 0.885), (0.92, 0.87), (0.98, 0.84), (1, 0.80)],
        top=[(0, 0.62), (0.03, 0.68), (0.1, 0.73), (0.3, 0.80), (0.33, 0.81), (0.5, 0.84), (0.8, 0.88),
             (0.95, 0.9), (1, 0.86)],
        bottom=[(0, 0.24), (0.05, 0.19), (0.93, 0.19), (1, 0.27)],
        shoulder=[(0, 0.52), (0.1, 0.66), (0.5, 0.72), (1, 0.76)],
        roof_h=[(0.32, 0), (0.335, 0.08), (0.45, 0.50), (0.52, 0.53), (0.68, 0.52), (0.76, 0.36), (0.81, 0.06),
                (0.82, 0)],
        roof_w=[(0.32, 0.74), (0.42, 0.68), (0.5, 0.64), (0.7, 0.64), (0.82, 0.72)],
        glass=dict(ws_end=0.45, roof_end=0.69, rear_end=0.815, side0=0.37, side1=0.775, pillars=[(0.565, 0.59)]),
        splits=dict(nose=0.06, cowl=0.33, door_r=0.73, deck=0.82, tail=0.95),
        paint=rgb(0x9a9aa0), seat=(0.08, 0.08, 0.09),
        front='rect', grille='slats', rear='blocks', bumper='black', exhaust='single', wheel_style='steel',
        rear_seat=True, red_calipers=False, extras=[],
    ),

    # Fiat Ponto: small five-door hatch.
    'tr_hatch': dict(
        root='TrHatch', lod=True, length=4.0, wheel_r=0.29, wheel_w=0.185, track=0.71, front_axle=0.8, wheelbase=2.5,
        width=[(0, 0.72), (0.03, 0.80), (0.08, 0.84), (0.5, 0.85), (0.94, 0.84), (0.99, 0.81), (1, 0.79)],
        top=[(0, 0.62), (0.03, 0.68), (0.1, 0.74), (0.25, 0.82), (0.30, 0.84), (0.5, 0.88), (0.95, 0.92),
             (0.99, 0.92), (1, 0.89)],
        bottom=[(0, 0.24), (0.05, 0.2), (0.94, 0.2), (1, 0.26)],
        shoulder=[(0, 0.55), (0.1, 0.66), (0.5, 0.74), (1, 0.78)],
        roof_h=[(0.29, 0), (0.305, 0.08), (0.42, 0.50), (0.50, 0.53), (0.80, 0.52), (0.92, 0.36), (0.98, 0.08),
                (0.99, 0)],
        roof_w=[(0.29, 0.72), (0.39, 0.66), (0.48, 0.62), (0.9, 0.62), (0.99, 0.68)],
        glass=dict(ws_end=0.42, roof_end=0.84, rear_end=0.98, side0=0.33, side1=0.82, pillars=[(0.565, 0.59)]),
        splits=dict(nose=0.05, cowl=0.30, door_r=0.75, deck=0.999, tail=0.955),
        paint=rgb(0x7a1f1f), seat=(0.1, 0.1, 0.11),
        front='twin_rect', grille='band', rear='tall', bumper='body', exhaust='single', wheel_style='steel',
        rear_seat=True, red_calipers=False, extras=[],
    ),

    # Skodo Octavio Kombi: estate that tows the caravan.
    'tr_estate': dict(
        root='TrEstate', lod=True, length=4.7, wheel_r=0.31, wheel_w=0.2, track=0.75, front_axle=0.92, wheelbase=2.72,
        width=[(0, 0.76), (0.03, 0.84), (0.08, 0.875), (0.5, 0.89), (0.95, 0.875), (0.99, 0.85), (1, 0.82)],
        top=[(0, 0.62), (0.03, 0.69), (0.1, 0.75), (0.28, 0.83), (0.30, 0.84), (0.5, 0.88), (0.95, 0.92),
             (0.99, 0.92), (1, 0.89)],
        bottom=[(0, 0.24), (0.05, 0.2), (0.95, 0.2), (1, 0.26)],
        shoulder=[(0, 0.53), (0.1, 0.67), (0.5, 0.74), (1, 0.78)],
        roof_h=[(0.29, 0), (0.305, 0.08), (0.42, 0.50), (0.49, 0.53), (0.93, 0.52), (0.975, 0.34), (0.993, 0.06),
                (1.0, 0)],
        roof_w=[(0.29, 0.74), (0.39, 0.68), (0.48, 0.65), (0.95, 0.65), (1.0, 0.70)],
        glass=dict(ws_end=0.42, roof_end=0.975, rear_end=1.0, side0=0.33, side1=0.955,
                   pillars=[(0.55, 0.575), (0.77, 0.79)]),
        splits=dict(nose=0.05, cowl=0.30, door_r=0.75, deck=0.999, tail=0.96),
        paint=rgb(0x1f3f7a), seat=(0.08, 0.08, 0.09),
        front='rect', grille='slats', chrome_grille=True, rear='tall', bumper='body', exhaust='single',
        wheel_style='steel', rear_seat=True, red_calipers=False, extras=['rails'],
    ),

    # Volkswagon Transpoorter: panel van, short nose, windows only up front.
    'tr_van': dict(
        root='TrVan', lod=True, length=5.3, wheel_r=0.34, wheel_w=0.215, track=0.83, front_axle=0.98, wheelbase=3.32,
        width=[(0, 0.86), (0.02, 0.93), (0.06, 0.97), (0.5, 0.98), (0.97, 0.97), (0.995, 0.95), (1, 0.93)],
        top=[(0, 0.80), (0.02, 0.88), (0.07, 0.98), (0.12, 1.04), (0.14, 1.06), (0.5, 1.10), (1, 1.10)],
        bottom=[(0, 0.30), (0.05, 0.26), (0.95, 0.26), (1, 0.32)],
        shoulder=[(0, 0.72), (0.1, 0.90), (0.5, 0.96), (1, 0.98)],
        roof_h=[(0.135, 0), (0.15, 0.12), (0.25, 0.78), (0.30, 0.85), (0.985, 0.85), (0.996, 0.5), (1.0, 0)],
        roof_w=[(0.135, 0.9), (0.25, 0.9), (1.0, 0.9)],
        glass=dict(ws_end=0.25, roof_end=0.999, rear_end=0.999, side0=0.16, side1=0.33, pillars=[]),
        splits=dict(nose=0.04, cowl=0.15, door_r=0.33, deck=0.999, tail=0.975),
        top_inset=0.05, gh_inset=0.05, seal_mat='Paint',
        paint=rgb(0xf2f2f2), seat=(0.1, 0.1, 0.11),
        front='rect', grille='slats', rear='tall', bumper='black', exhaust='single', wheel_style='steel',
        red_calipers=False, extras=[],
    ),

    # Politie Volvi V70: white estate with blue and orange striping and a light bar.
    'police': dict(
        root='Police', lod=True, length=4.8, wheel_r=0.31, wheel_w=0.205, track=0.76, front_axle=0.94, wheelbase=2.76,
        width=[(0, 0.76), (0.03, 0.85), (0.08, 0.885), (0.5, 0.90), (0.95, 0.885), (0.99, 0.86), (1, 0.83)],
        top=[(0, 0.64), (0.03, 0.71), (0.1, 0.77), (0.29, 0.85), (0.31, 0.86), (0.5, 0.90), (0.95, 0.93),
             (0.99, 0.93), (1, 0.90)],
        bottom=[(0, 0.24), (0.05, 0.2), (0.95, 0.2), (1, 0.26)],
        shoulder=[(0, 0.55), (0.1, 0.68), (0.5, 0.76), (1, 0.80)],
        roof_h=[(0.30, 0), (0.315, 0.08), (0.43, 0.50), (0.50, 0.53), (0.93, 0.52), (0.975, 0.34), (0.993, 0.06),
                (1.0, 0)],
        roof_w=[(0.30, 0.74), (0.40, 0.68), (0.49, 0.65), (0.95, 0.65), (1.0, 0.70)],
        glass=dict(ws_end=0.43, roof_end=0.975, rear_end=1.0, side0=0.34, side1=0.955,
                   pillars=[(0.56, 0.585), (0.78, 0.80)]),
        splits=dict(nose=0.05, cowl=0.31, door_r=0.76, deck=0.999, tail=0.96),
        paint=rgb(0xf4f6f8), seat=(0.06, 0.06, 0.07),
        front='slim', grille='band', rear='tall', bumper='body', exhaust='single', wheel_style='fivespoke',
        rear_seat=True, red_calipers=False, extras=['police', 'antenna'],
    ),
}
