import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';

import { SupabaseService } from '../core/supabase.service';

export const RoleGuard: CanActivateFn = (_route, state) => {
  const supabase = inject(SupabaseService);
  const router = inject(Router);
  if (supabase.session() && supabase.isAdmin()) return true;
  if (supabase.session()) return router.createUrlTree(['/catalog']);
  return router.createUrlTree(['/login'], { queryParams: { returnUrl: state.url } });
};
