import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { SupabaseService } from '../core/supabase.service';

export const AuthGuard: CanActivateFn = (_route, state) => {
  const supabase = inject(SupabaseService);
  const router = inject(Router);
  if (supabase.session()) return true;
  return router.createUrlTree(['/login'], { queryParams: { returnUrl: state.url } });
};
