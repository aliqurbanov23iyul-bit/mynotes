// Catalog is populated only from the authenticated TMDB proxy. No sample titles.
export {workspace as storage} from './services/workspace-service.js';
export let movies=[];
export function setMovies(values){movies=values;}
