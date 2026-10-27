[out:json][timeout:120];
(
 nwr[man_made~"^(water_tower|windmill|tower|chimney|silo|mast)$"](52.20,6.22,52.43,6.93);
 nwr["generator:source"=wind](52.20,6.22,52.43,6.93);
 nwr[historic=windmill](52.20,6.22,52.43,6.93);
 nwr[amenity=fuel](52.20,6.22,52.43,6.93);
 nwr[building=church](52.20,6.22,52.43,6.93);
 nwr[amenity=place_of_worship](52.20,6.22,52.43,6.93);
 nwr[tourism~"^(attraction|theme_park)$"](52.20,6.22,52.43,6.93);
 nwr[leisure~"^(stadium|water_park)$"](52.20,6.22,52.43,6.93);
 nwr[aeroway=aerodrome](52.20,6.22,52.43,6.93);
 nwr[amenity=fast_food][brand](52.20,6.22,52.43,6.93);
);
out tags center;
