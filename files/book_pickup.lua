-- LuaComponent of the books (entities/spellbook.xml, palm_quire.xml, great_tome.xml): the witch picks one up - the
-- first time in the run it becomes theirs (books.lua book_owned): the sheets that waited for a book this big are pasted in,
-- the shops and the bosses stop offering it.
dofile_once( "mods/witch_notebook/files/books.lua" )
dofile_once( "mods/witch_notebook/files/book_key.lua" )

function item_pickup( entity_item, entity_who_picked, item_name )
	book_first_pickup( book_key_of( entity_item ), entity_who_picked )
end
