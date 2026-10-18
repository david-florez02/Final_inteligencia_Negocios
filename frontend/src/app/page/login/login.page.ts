import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { Router, RouterLink } from '@angular/router';

import { SupabaseService } from '../../core/supabase.service';

@Component({
  selector: 'app-login-page',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink, MatCardModule, MatFormFieldModule, MatInputModule, MatButtonModule],
  template: `
    <mat-card class="login-card">
      <mat-card-header><mat-card-title>Iniciar sesión</mat-card-title></mat-card-header>
      <mat-card-content>
        <form [formGroup]="form" (ngSubmit)="submit()" class="form">
          <mat-form-field appearance="outline">
            <mat-label>Email</mat-label>
            <input matInput type="email" formControlName="email" required>
            @if (form.controls.email.hasError('required')) { <mat-error>El email es obligatorio</mat-error> }
            @else if (form.controls.email.hasError('email')) { <mat-error>Email no válido</mat-error> }
          </mat-form-field>
          <mat-form-field appearance="outline">
            <mat-label>Contraseña</mat-label>
            <input matInput type="password" formControlName="password" required>
            @if (form.controls.password.hasError('required')) { <mat-error>La contraseña es obligatoria</mat-error> }
          </mat-form-field>
          @if (error()) { <p class="error">{{ error() }}</p> }
          <button mat-flat-button color="primary" type="submit" [disabled]="loading()">Entrar</button>
        </form>
        <p class="hint">¿No tienes cuenta? <a routerLink="/register">Regístrate</a></p>
      </mat-card-content>
    </mat-card>
  `,
  styles: [`
    .login-card { max-width: 420px; margin: 48px auto; }
    .form { display: flex; flex-direction: column; gap: 8px; }
    .error { color: #c62828; }
    .hint { margin-top: 16px; }
  `],
})
export class LoginPage {
  private fb = inject(FormBuilder);
  private supabase = inject(SupabaseService);
  private router = inject(Router);

  readonly error = signal<string | null>(null);
  readonly loading = signal(false);
  readonly form = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required]],
  });

  async submit(): Promise<void> {
    if (this.form.invalid) { this.form.markAllAsTouched(); return; }
    this.loading.set(true);
    this.error.set(null);
    const { email, password } = this.form.getRawValue();
    const { error } = await this.supabase.signIn(email, password);
    this.loading.set(false);
    if (error) { this.error.set(error); return; }
    void this.router.navigate([this.supabase.isAdmin() ? '/admin' : '/catalog']);
  }
}
