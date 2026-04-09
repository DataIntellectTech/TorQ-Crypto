trade:([]time:`timestamp$();sym:`g#`symbol$();venue:`symbol$();price:`float$();size:`float$();side:`symbol$();venue_sym:`symbol$();seq:`long$())
quote:([]time:`timestamp$();sym:`g#`symbol$();venue:`symbol$();bid:`float$();ask:`float$();bsize:`float$();asize:`float$();venue_sym:`symbol$())
lastprice:([sym:`symbol$();venue:`symbol$()] time:`timestamp$();price:`float$();bid:`float$();ask:`float$();mid:`float$())
consolidatedmid:([]time:`timestamp$();sym:`g#`symbol$();mid:`float$();n_venues:`int$();spread_dispersion:`float$();outlier_flag:`boolean$())


