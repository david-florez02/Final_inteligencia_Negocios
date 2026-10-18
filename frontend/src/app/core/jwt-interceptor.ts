import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { from, switchMap } from 'rxjs';

import { SupabaseService } from './supabase.service';

export const jwtInterceptor: HttpInterceptorFn = (req, next) => {
  const supabase = inject(SupabaseService);
  return from(supabase.authHeaders()).pipe(
    switchMap((headers) => {
      const authReq = req.clone({ setHeaders: headers });
      return next(authReq);
    })
  );
};
