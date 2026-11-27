-- Deshace el cambio 010.
begin;

alter default privileges for role postgres grant execute on functions to public;

commit;
