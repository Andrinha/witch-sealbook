-- The death script books.lua gives every boss (books_patch_bosses): the first boss the witch kills leaves a Great Tome.
dofile_once( "mods/witch_notebook/files/books.lua" )

function death( damage_type_bit_field, damage_message, entity_thats_responsible, drop_items )
	book_boss_drop( GetUpdatedEntityID() )
end
