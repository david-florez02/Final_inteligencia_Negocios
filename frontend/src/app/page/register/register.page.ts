import { Component, inject, signal } from '@angular/core';
import { FormBuilder, ReactiveFormsModule, Validators } from '@angular/forms';
import { MatButtonModule } from '@angular/material/button';
import { MatCardModule } from '@angular/material/card';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatInputModule } from '@angular/material/input';
import { Router, RouterLink } from '@angular/router';

import { SupabaseService } from '../../core/supabase.service';

@Component({
  selector: 'app-register-page',
  standalone: true,
  imports: [ReactiveFormsModule, RouterLink, MatCardModule, MatFormFieldModule, MatInputModule, MatButtonModule],
  template: `
    <mat-card class="register-card">
      <mat-card-header><mat-card-title>Crear cuenta</mat-card-title></mat-card-header>
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
            <input matInput type="password" formControlName="password" required minlength="6">
            @if (form.controls.password.hasError('minlength')) { <mat-error>Mínimo 6 caracteres</mat-error> }
          </mat-form-field>
          <mat-form-field appearance="outline">
            <mat-label>Nombre completo</mat-label>
            <input matInput formControlName="fullName" required>
          </mat-form-field>
          @if (error()) { <p class="error">{{ error() }}</p> }
          @if (success()) { <p class="success">{{ success() }}</p> }
          <button mat-flat-button color="primary" type="submit" [disabled]="loading()">Registrarse</button>
        </form>
        <p class="hint">¿Ya tienes cuenta? <a routerLink="/login">Inicia sesión</a></p>
      </mat-card-content>
    </mat-card>
  `,
  styles: [`
    .register-card { max-width: 420px; margin: 48px auto; }
    .form { display: flex; flex-direction: column; gap: 8px; }
    .error { color: #c62828; }
    .success { color: #2e7d32; }
    .hint { margin-top: 16px; }
  `],
})
export class RegisterPage {
  private fb = inject(FormBuilder);
  private supabase = inject(SupabaseService);
  private router = inject(Router);

  readonly error = signal<string | null>(null);
  readonly success = signal<string | null>(null);
  readonly loading = signal(false);
  readonly form = this.fb.nonNullable.group({
    email: ['', [Validators.required, Validators.email]],
    password: ['', [Validators.required, Validators.minLength(6)]],
    fullName: ['', [Validators.required]],
  });

  async submit(): Promise<void> {
    if (this.form.invalid) { this.form.markAllAsTouched(); return; }
    this.loading.set(true);
    this.error.set(null);
    const { email, password, fullName } = this.form.getRawValue();
    const { error } = await this.supabase.signUp(email, password);
    this.loading.set(false);
    if (error) { this.error.set(error); return; }

    if (this.supabase.session()) {
      await fetch('/api/profile/me', {
        method: 'PUT',
        headers: await this.supabase.authHeaders(),
        body: JSON.stringify({ full_name: fullName }),
      }).catch(() => undefined);
      void this.router.navigate(['/catalog']);
    } else {
      this.success.set('Cuenta creada. Revisa tu correo para confirmar el registro.');
    }
  }
}
